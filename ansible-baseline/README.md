# Baseline для серверов wax.su

Единая базовая настройка всех хостов: пакеты, время, админы и SSH-ключи,
sudo, жёсткий sshd, ufw, fail2ban, автообновления безопасности, sysctl, journald.

## Структура
```
ansible.cfg
baseline.yml                    # плейбук
inventory/
  hosts.ini                     # хосты и группы
  group_vars/all.yml            # общие настройки (список IP для SSH и т.д.)
  host_vars/git.wax.su.yml      # правила конкретного хоста
roles/baseline/                 # сама роль
```

## Первый запуск
```bash
ansible-galaxy collection install community.general ansible.posix   # если ещё нет
ansible all -m ping
ansible-playbook baseline.yml --check --diff          # посмотреть, что изменится
ansible-playbook baseline.yml --limit stage.wax.su    # сначала на одном хосте
ansible-playbook baseline.yml                         # потом на всех
```

Только часть роли:
```bash
ansible-playbook baseline.yml --tags ufw
ansible-playbook baseline.yml --tags ssh,fail2ban
```

## Что важно
- Перед отключением входа по паролю роль проверяет, что у пользователя есть
  `authorized_keys`, иначе останавливается.
- ufw: сначала добавляются разрешения SSH, потом включается файрвол.
  Существующие правила не удаляются — роль только добавляет.
- Пакеты из `baseline_unattended_blacklist` (gitlab, ansible) автообновлениями не трогаются.
- Добавить IP для SSH на все хосты: допишите в `baseline_ssh_allowed` и запустите `--tags ufw`.
