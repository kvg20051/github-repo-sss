import argparse
import fnmatch
import glob
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


class CandidateConfig:
    def __init__(self, config_root, target, candidate, workspace):
        self.config_root = Path(config_root).absolute()
        self.target = Path(target).absolute()
        self.candidate = Path(candidate)
        self.workspace = Path(workspace)
        self.copies = {}
        self.used_candidate = False

    def matches_target(self, pattern):
        parts = Path(pattern).parts
        target_parts = self.target.parts
        return len(parts) == len(target_parts) and all(
            fnmatch.fnmatchcase(part, pattern_part)
            for part, pattern_part in zip(target_parts, parts)
        )

    def clone(self, source, stack=()):
        source = Path(source).absolute()
        if source in stack or len(stack) >= 16:
            raise ValueError("Cyclic or excessively deep SSH Include")
        if source in self.copies:
            return self.copies[source]
        destination = self.workspace / ("config-" + str(len(self.copies)))
        self.copies[source] = destination
        if source == self.target:
            self.used_candidate = True
            content = self.candidate.read_text()
        else:
            content = source.read_text()
        output = []
        for line in content.splitlines(keepends=True):
            stripped = line.lstrip()
            if not stripped or stripped.startswith("#"):
                output.append(line)
                continue
            keyword = stripped.split(None, 1)[0].split("=", 1)[0]
            if keyword.lower() != "include":
                output.append(line)
                continue
            tokens = shlex.split(stripped[len("include"):].lstrip("= \t"), comments=True)
            if not tokens:
                raise ValueError("Empty SSH Include")
            included = []
            for pattern in tokens:
                expanded = Path(pattern)
                if not expanded.is_absolute():
                    expanded = self.config_root / expanded
                matching = set(glob.glob(str(expanded)))
                if self.matches_target(str(expanded)):
                    matching.add(str(self.target))
                included.extend(
                    self.clone(Path(match), stack + (source,)) for match in sorted(matching)
                )
            if included:
                output.append("Include " + " ".join('"' + str(path) + '"' for path in included) + "\n")
        destination.write_text("".join(output))
        return destination


def validate(args):
    with tempfile.TemporaryDirectory(prefix="baseline-sshd-") as directory:
        configuration = CandidateConfig(args.config_root, args.target, args.candidate, directory)
        main = configuration.clone(args.main)
        if not configuration.used_candidate:
            raise ValueError("The main SSH configuration does not Include the baseline drop-in")
        subprocess.run([args.sshd, "-t", "-f", str(main)], check=True)
        result = subprocess.run(
            [args.sshd, "-T", "-f", str(main)],
            check=True, text=True, capture_output=True,
        )
        effective = {}
        for line in result.stdout.splitlines():
            key, _, value = line.partition(" ")
            effective.setdefault(key, []).append(value)
        expected = {
            "passwordauthentication": args.password_auth,
            "permitrootlogin": args.root_login.replace("prohibit-password", "without-password"),
            "pubkeyauthentication": "yes",
            "kbdinteractiveauthentication": "no",
        }
        for key, value in expected.items():
            if effective.get(key) != [value]:
                raise ValueError("Effective SSH setting differs from baseline: " + key)
        print("Complete candidate SSH configuration is valid")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--target", default="/etc/ssh/sshd_config.d/10-baseline.conf")
    parser.add_argument("--main", default="/etc/ssh/sshd_config")
    parser.add_argument("--config-root", default="/etc/ssh")
    parser.add_argument("--sshd", default="/usr/sbin/sshd")
    parser.add_argument("--password-auth", required=True)
    parser.add_argument("--root-login", required=True)
    args = parser.parse_args()
    try:
        validate(args)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
