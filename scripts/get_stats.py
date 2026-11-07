#!/usr/bin/env python3
import time, glob, os, json, subprocess

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
    # 1. Sample CPU and GPU RC6 at start of 100ms window
    t1 = time.time()
    try:
        with open("/proc/stat") as f:
            c1 = [float(x) for x in f.readline().strip().split()[1:]]
    except Exception:
        c1 = [0, 0, 0, 0, 0, 0, 0, 0]

    rc6_path = "/sys/class/drm/card1/power/rc6_residency_ms"
    if not os.path.exists(rc6_path):
        rc6_path = "/sys/class/drm/card1/gt/gt0/rc6_residency_ms"
    if not os.path.exists(rc6_path):
        for p in glob.glob("/sys/class/drm/card*/power/rc6_residency_ms"):
            rc6_path = p
            break
    r1 = None
    try:
        with open(rc6_path) as f:
            r1 = int(f.read().strip())
    except Exception:
        pass

    # 2. Non-blocking sensor reads while in sampling interval
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

    # 3. Fan speed (Dell SMM or generic Linux hwmon fan)
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

    # 4. CPU Frequencies (Average active clock)
    freqs = []
    for f in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq"):
        try:
            with open(f) as ff:
                freqs.append(int(ff.read().strip()))
        except Exception:
            pass
    cpu_freq = round((sum(freqs) / len(freqs)) / 1000000.0, 2) if freqs else 1.8

    # 5. GPU Frequency & Limits
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

    # 6. Memory & System Load
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

    # 7. Sleep remaining of 110ms sample window
    elapsed = time.time() - t1
    if elapsed < 0.11:
        time.sleep(0.11 - elapsed)

    # 8. End of sample window
    t2 = time.time()
    try:
        with open("/proc/stat") as f:
            c2 = [float(x) for x in f.readline().strip().split()[1:]]
    except Exception:
        c2 = c1

    r2 = None
    if r1 is not None and os.path.exists(rc6_path):
        try:
            with open(rc6_path) as f:
                r2 = int(f.read().strip())
        except Exception:
            pass

    # CPU % delta
    d_idle = (c2[3] + c2[4]) - (c1[3] + c1[4])
    d_tot = sum(c2) - sum(c1)
    cpu_pct = max(0.0, min(100.0, round(100.0 * (1.0 - d_idle / d_tot), 1))) if d_tot > 0 else 0.0

    # Intel GPU % utilization: Combines dynamic RPS hardware frequency scaling with RC6 sleep residency
    if gpu_mhz > gpu_min_mhz:
        freq_ratio = (gpu_mhz - gpu_min_mhz) / float(max(1, gpu_max_mhz - gpu_min_mhz))
        gpu_pct = min(100.0, round(10.0 + freq_ratio * 90.0, 1))
    else:
        # At minimum idle clock (300 MHz), check RC6 sleep residency
        if r1 is not None and r2 is not None:
            dt_ms = (t2 - t1) * 1000.0
            d_rc6 = r2 - r1
            sleep_pct = (d_rc6 / dt_ms) * 100.0 if dt_ms > 0 else 100.0
            if sleep_pct < 75.0:
                gpu_pct = round(max(0.0, min(10.0, (75.0 - sleep_pct) / 75.0 * 10.0)), 1)
            else:
                gpu_pct = 0.0
        else:
            gpu_pct = 0.0

    return {
        "cpu_model": get_cpu_model(),
        "gpu_model": get_gpu_model(),
        "cpu_pct": cpu_pct,
        "cpu_temp": cpu_temp,
        "cpu_freq": cpu_freq,
        "cores": cores,
        "gpu_mhz": gpu_mhz,
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
