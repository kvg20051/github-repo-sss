import argparse
import difflib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


def render_rules(original, interface, sources):
    begin = "# BEGIN baseline-" + interface + "-nat"
    end = "# END baseline-" + interface + "-nat"
    lines = original.splitlines()
    if lines.count(begin) != lines.count(end) or lines.count(begin) > 1:
        raise ValueError("Malformed managed NAT block")
    if begin in lines:
        start, stop = lines.index(begin), lines.index(end)
        if stop <= start:
            raise ValueError("Malformed managed NAT block")
        del lines[start:stop + 1]
    tables = [index for index, line in enumerate(lines) if line.strip() == "*nat"]
    if len(tables) > 1:
        raise ValueError("Multiple NAT tables: reconcile before.rules manually")
    rules = [
        "-A POSTROUTING -s " + source + " ! -o " + interface +
        " -m comment --comment baseline-" + interface + "-nat -j MASQUERADE"
        for source in sources
    ]
    block = [begin] + rules + [end]
    if not tables:
        return "\n".join(["*nat", ":POSTROUTING ACCEPT [0:0]"] + block + ["COMMIT", ""] + lines) + "\n"
    start = tables[0]
    stop = next(
        (index for index in range(start + 1, len(lines)) if lines[index].strip() == "COMMIT"),
        None,
    )
    if stop is None or any(line.startswith("*") for line in lines[start + 1:stop]):
        raise ValueError("Unterminated NAT table")
    if not any(line.startswith(":POSTROUTING ") for line in lines[start + 1:stop]):
        lines.insert(start + 1, ":POSTROUTING ACCEPT [0:0]")
        stop += 1
    lines[stop:stop] = block
    return "\n".join(lines) + "\n"


def detect_sources(interface):
    result = subprocess.run(
        ["ip", "-j", "-4", "address", "show", "dev", interface],
        check=True, capture_output=True, text=True,
    )
    sources = set()
    for device in json.loads(result.stdout):
        for address in device.get("addr_info", []):
            if address.get("family") == "inet":
                network = ipaddress.ip_interface(
                    address["local"] + "/" + str(address["prefixlen"])
                ).network
                if network.prefixlen == 32:
                    raise ValueError("An interface /32 does not identify client networks; pass --source CIDR")
                sources.add(str(network))
    if not sources:
        raise ValueError("No IPv4 subnet found; pass --source CIDR explicitly")
    return sorted(sources)


def main():
    parser = argparse.ArgumentParser(description="Preview or apply IPv4 masquerading through UFW.")
    parser.add_argument("--interface", default="wg8")
    parser.add_argument("--source", action="append", default=[])
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,15}", args.interface):
        parser.error("Invalid interface name")
    if sys.platform != "linux" or os.geteuid() != 0:
        parser.error("Run on the Linux gateway with sudo, including for preview")
    try:
        sources = args.source or detect_sources(args.interface)
        networks = [ipaddress.ip_network(source, strict=False) for source in sources]
        if any(network.version != 4 or network.prefixlen == 0 for network in networks):
            raise ValueError("Use specific IPv4 source networks, not 0.0.0.0/0")
        sources = sorted(set(map(str, networks)))
        target = Path("/etc/ufw/before.rules")
        original = target.read_text()
        updated = render_rules(original, args.interface, sources)
        if updated == original:
            print("No changes required")
            return 0
        print("IPv4 sources: " + ", ".join(sources))
        print("".join(difflib.unified_diff(
            original.splitlines(True), updated.splitlines(True),
            fromfile=str(target), tofile=str(target) + " (candidate)",
        )), end="")
        with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as candidate:
            candidate.write(updated)
            candidate_path = Path(candidate.name)
        try:
            with candidate_path.open() as candidate_input:
                subprocess.run(
                    ["iptables-restore", "--test", "--noflush"],
                    stdin=candidate_input, check=True,
                )
            if not args.apply:
                print("Preview only. Add --apply to write and reload UFW.")
                return 0
            backup = target.with_name(target.name + ".baseline-" + str(time.time_ns()) + ".bak")
            shutil.copy2(target, backup)
            shutil.copystat(target, candidate_path)
            target_stat = target.stat()
            os.chown(candidate_path, target_stat.st_uid, target_stat.st_gid)
            os.replace(candidate_path, target)
            try:
                subprocess.run(["ufw", "reload"], check=True)
            except (OSError, subprocess.CalledProcessError):
                shutil.copy2(backup, target)
                subprocess.run(["ufw", "reload"], check=True)
                raise
            print("Applied. Backup: " + str(backup))
        finally:
            candidate_path.unlink(missing_ok=True)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
