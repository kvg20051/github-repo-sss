import argparse
import os
import shlex
import subprocess
import sys


def command_for(args):
    command = [
        args.executable, "-S", "none", "-T",
        "-o", "ControlMaster=no",
        "-o", "ControlPath=none",
        "-o", "ControlPersist=no",
        "-o", "BatchMode=yes",
        "-o", "PreferredAuthentications=publickey",
        "-o", "PubkeyAuthentication=yes",
        "-o", "PasswordAuthentication=no",
        "-o", "KbdInteractiveAuthentication=no",
        "-o", "GSSAPIAuthentication=no",
        "-o", "HostbasedAuthentication=no",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "ConnectTimeout=10",
        "-o", "ConnectionAttempts=1",
        "-o", "ClearAllForwardings=yes",
        "-o", "RemoteCommand=none",
        "-o", "RequestTTY=no",
        "-p", str(args.port), "-l", args.user,
    ]
    if args.key:
        command.extend(["-i", os.path.expanduser(args.key), "-o", "IdentitiesOnly=yes"])
    command.extend(shlex.split(args.common_args))
    command.extend(shlex.split(args.extra_args))
    command.extend(["--", args.host, "printf '%s\\n' baseline-ssh-probe-ok"])
    return command


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--key", default="")
    parser.add_argument("--common-args", default="")
    parser.add_argument("--extra-args", default="")
    parser.add_argument("--executable", default="ssh")
    args = parser.parse_args()
    if not args.host or not args.user or not 1 <= args.port <= 65535:
        parser.error("A valid SSH host, user and port are required")
    try:
        result = subprocess.run(
            command_for(args), text=True, capture_output=True, timeout=30,
            stdin=subprocess.DEVNULL,
        )
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1
    if result.returncode or "baseline-ssh-probe-ok" not in result.stdout.splitlines():
        print(result.stderr, file=sys.stderr)
        print("Independent public-key SSH login failed", file=sys.stderr)
        return 1
    print("Independent public-key SSH login succeeded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
