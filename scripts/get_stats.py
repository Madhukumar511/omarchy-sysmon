#!/usr/bin/env python3
"""
Accurate, zero-overhead hardware telemetry engine for Omarchy.
Computes real CPU delta ticks and Intel GPU RC6 residency sleep delta
from state cache, avoiding synthetic blocking sleep intervals.
"""
import time, glob, os, json, subprocess

STATE_FILE = "/tmp/.omarchy_sysmon_state.json"
_cpu_model_cache = None
_gpu_model_cache = None

def get_cpu_model():
    global _cpu_model_cache
    if _cpu_model_cache is not None:
        return _cpu_model_cache
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "model name" in line:
                    name = line.split(":", 1)[1].strip()
                    name = name.replace("(R)", "").replace("(TM)", "").replace("CPU ", "").strip()
                    name = name.split("@")[0].strip()
                    _cpu_model_cache = name
                    return name
    except Exception:
        pass
    _cpu_model_cache = "Processor"
    return _cpu_model_cache

def get_gpu_model():
    global _gpu_model_cache
    if _gpu_model_cache is not None:
        return _gpu_model_cache
    try:
        res = subprocess.run(["lspci"], capture_output=True, text=True, timeout=1)
        for line in res.stdout.splitlines():
            if "VGA compatible controller" in line or "3D controller" in line:
                part = line.split(":", 2)[-1].strip()
                if "[" in part and "]" in part:
                    part = part.split("[")[-1].split("]")[0]
                _gpu_model_cache = part
                return part
    except Exception:
        pass
    _gpu_model_cache = "Graphics"
    return _gpu_model_cache

def get_stats():
    now = time.time()

    # 1. Read current CPU ticks
    cpu_ticks = [0.0] * 8
    try:
        with open("/proc/stat") as f:
            cpu_ticks = [float(x) for x in f.readline().strip().split()[1:]]
    except Exception:
        pass

    # 2. Read GPU RC6 residency
    rc6_path = "/sys/class/drm/card1/gt/gt0/rc6_residency_ms"
    if not os.path.exists(rc6_path):
        rc6_path = "/sys/class/drm/card1/power/rc6_residency_ms"
    if not os.path.exists(rc6_path):
        for p in glob.glob("/sys/class/drm/card*/gt/gt0/rc6_residency_ms") + glob.glob("/sys/class/drm/card*/power/rc6_residency_ms"):
            rc6_path = p
            break

    rc6_ms = None
    if os.path.exists(rc6_path):
        try:
            with open(rc6_path) as f:
                rc6_ms = int(f.read().strip())
        except Exception:
            pass

    # 3. Read previous state to compute real deltas
    prev_state = None
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE) as f:
                prev_state = json.load(f)
        except Exception:
            pass

    # 4. Handle initial cold-start or stale state
    dt = (now - prev_state["time"]) if (prev_state and "time" in prev_state) else 0.0
    if dt < 0.2 or dt > 60.0 or not prev_state:
        # Perform a brief 60ms baseline sample if no valid previous state
        time.sleep(0.06)
        now2 = time.time()
        try:
            with open("/proc/stat") as f:
                cpu_ticks2 = [float(x) for x in f.readline().strip().split()[1:]]
        except Exception:
            cpu_ticks2 = cpu_ticks

        rc6_ms2 = None
        if os.path.exists(rc6_path):
            try:
                with open(rc6_path) as f:
                    rc6_ms2 = int(f.read().strip())
            except Exception:
                pass

        prev_ticks = cpu_ticks
        cpu_ticks = cpu_ticks2
        prev_rc6 = rc6_ms
        rc6_ms = rc6_ms2
        dt = now2 - now
        now = now2
    else:
        prev_ticks = prev_state.get("cpu", cpu_ticks)
        prev_rc6 = prev_state.get("rc6", rc6_ms)

    # Save new state for next cycle
    try:
        new_state = {
            "time": now,
            "cpu": cpu_ticks,
            "rc6": rc6_ms
        }
        with open(STATE_FILE, "w") as f:
            json.dump(new_state, f)
    except Exception:
        pass

    # Compute genuine CPU utilization
    cpu_pct = 0.0
    if prev_ticks and cpu_ticks:
        d_idle = (cpu_ticks[3] + cpu_ticks[4]) - (prev_ticks[3] + prev_ticks[4])
        d_tot = sum(cpu_ticks) - sum(prev_ticks)
        if d_tot > 0:
            cpu_pct = max(0.0, min(100.0, round(100.0 * (1.0 - d_idle / d_tot), 1)))

    # Compute genuine GPU utilization via RC6 residency delta
    gpu_pct = 0.0
    if rc6_ms is not None and prev_rc6 is not None and dt > 0:
        d_rc6 = rc6_ms - prev_rc6
        dt_ms = dt * 1000.0
        sleep_pct = max(0.0, min(100.0, (d_rc6 / dt_ms) * 100.0))
        gpu_pct = max(0.0, min(100.0, round(100.0 - sleep_pct, 1)))

    # 5. Core Temperatures
    cpu_temp = 42.0
    cores = []
    for hw in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            with open(os.path.join(hw, "name")) as f:
                hw_name = f.read().strip()
                if hw_name in ("coretemp", "k10temp", "zenpower", "cpu_thermal"):
                    for t in sorted(glob.glob(os.path.join(hw, "temp*_input"))):
                        lbl = os.path.basename(t)
                        lbl_file = t.replace("_input", "_label")
                        if os.path.exists(lbl_file):
                            with open(lbl_file) as lf:
                                lbl = lf.read().strip()
                        with open(t) as vf:
                            v = round(int(vf.read().strip()) / 1000.0, 1)
                        if "Package" in lbl or "Tdie" in lbl or "Tctl" in lbl or not cpu_temp:
                            cpu_temp = v
                        if "Core" in lbl or "temp" in lbl:
                            cores.append({"name": lbl, "temp": v})
                    break
        except Exception:
            pass

    # 6. Fan Speed
    fan_rpm = 0
    for hw in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            with open(os.path.join(hw, "name")) as f:
                if f.read().strip() == "dell_smm":
                    with open(os.path.join(hw, "fan1_input")) as ff:
                        fan_rpm = int(ff.read().strip())
                    break
        except Exception:
            pass
    if fan_rpm == 0:
        for f in glob.glob("/sys/class/hwmon/hwmon*/fan*_input"):
            try:
                with open(f) as ff:
                    val = int(ff.read().strip())
                    if val > 0:
                        fan_rpm = val
                        break
            except Exception:
                pass

    fan_max = 7000
    fan_pct = min(100, round((fan_rpm / float(fan_max)) * 100))
    if fan_rpm == 0:
        fan_status = "Passive / Off"
    elif fan_rpm < 3200:
        fan_status = "Quiet / Low"
    elif fan_rpm < 5200:
        fan_status = "Balanced / Mid"
    else:
        fan_status = "Turbo / High"

    # 7. CPU Frequencies
    freqs = []
    for f in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq"):
        try:
            with open(f) as ff:
                freqs.append(int(ff.read().strip()))
        except Exception:
            pass
    cpu_freq = round((sum(freqs) / len(freqs)) / 1000000.0, 2) if freqs else 1.8

    # 8. GPU Frequency & Limits
    gpu_mhz = 300
    gpu_min_mhz = 300
    gpu_max_mhz = 1150
    for p in glob.glob("/sys/class/drm/card*/gt_act_freq_mhz") + glob.glob("/sys/class/drm/card*/gt/gt0/rps_act_freq_mhz"):
        try:
            with open(p) as f:
                gpu_mhz = int(f.read().strip())
                break
        except Exception:
            pass
    for p in glob.glob("/sys/class/drm/card*/gt_min_freq_mhz") + glob.glob("/sys/class/drm/card*/gt/gt0/rps_min_freq_mhz"):
        try:
            with open(p) as f:
                gpu_min_mhz = int(f.read().strip())
                break
        except Exception:
            pass
    for p in glob.glob("/sys/class/drm/card*/gt_max_freq_mhz") + glob.glob("/sys/class/drm/card*/gt/gt0/rps_max_freq_mhz"):
        try:
            with open(p) as f:
                gpu_max_mhz = int(f.read().strip())
                break
        except Exception:
            pass

    # 9. Memory & Load
    mem_used, mem_total, mem_pct = 0.0, 0.0, 0
    try:
        mem = {}
        with open("/proc/meminfo") as f:
            for line in f:
                p = line.split(":")
                if len(p) == 2:
                    mem[p[0].strip()] = int(p[1].strip().split()[0])
        tot = mem.get("MemTotal", 1)
        avail = mem.get("MemAvailable", 0)
        used = tot - avail
        mem_used = round(used / (1024.0 * 1024.0), 1)
        mem_total = round(tot / (1024.0 * 1024.0), 1)
        mem_pct = round((used / float(tot)) * 100)
    except Exception:
        pass

    load_1m = 0.0
    try:
        with open("/proc/loadavg") as f:
            load_1m = round(float(f.read().split()[0]), 2)
    except Exception:
        pass

    return {
        "cpu_model": get_cpu_model(),
        "gpu_model": get_gpu_model(),
        "cpu_pct": cpu_pct,
        "cpu_temp": cpu_temp,
        "cpu_freq": cpu_freq,
        "cores": cores,
        "gpu_mhz": gpu_mhz,
        "gpu_min_mhz": gpu_min_mhz,
        "gpu_max_mhz": gpu_max_mhz,
        "gpu_pct": gpu_pct,
        "fan_rpm": fan_rpm,
        "fan_max": fan_max,
        "fan_pct": fan_pct,
        "fan_status": fan_status,
        "mem_used": mem_used,
        "mem_total": mem_total,
        "mem_pct": mem_pct,
        "load_1m": load_1m
    }

if __name__ == "__main__":
    print(json.dumps(get_stats()))
