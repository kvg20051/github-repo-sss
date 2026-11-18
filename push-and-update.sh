set -euo pipefail

repo_url="git@github.com:kvg20051/github-repo-sss.git"

branch="$(git symbolic-ref --quiet --short HEAD)" || {
    echo "Запустите скрипт из репозитория с выбранной веткой." >&2
    exit 1
}

# При неудачном push скрипт остановится.
git push "$repo_url" "HEAD:refs/heads/$branch"

update_host() {
    local host="$1"
    local directory="$2"

    printf '\nОбновление %s, ветка %s\n' "$host" "$branch"

    {
        # Передаём значения с экранированием для удалённого Bash.
        printf 'set -euo pipefail\n'
        printf 'cd -- %q\n' "$directory"
        printf 'expected_branch=%q\n' "$branch"
        printf 'repo_url=%q\n' "$repo_url"

        cat <<'REMOTE'
current_branch="$(git symbolic-ref --quiet --short HEAD)"

if [[ "$current_branch" != "$expected_branch" ]]; then
    echo "Ошибка: выбрана ветка $current_branch, нужна $expected_branch." >&2
    exit 1
fi

changes="$(git status --porcelain)"
if [[ -n "$changes" ]]; then
    echo "Ошибка: есть локальные изменения или неотслеживаемые файлы:" >&2
    printf '%s\n' "$changes" >&2
    exit 1
fi

git -c pull.rebase=false pull --ff-only "$repo_url" "$expected_branch"
git log -1 --format='%h %s'
REMOTE
    } | ssh -T -o ConnectTimeout=15 "$host" bash -s
}

update_host "kvg@mail" "/home/kvg/github-repo-sss"
update_host "kvg@ficus" "/home/kvg/_Git_projects/github-repo-sss"

echo "Обновление обоих хостов завершено."
