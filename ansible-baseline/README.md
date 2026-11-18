# Baseline для серверов wax.su

Ansible-роль `baseline` настраивает базовое окружение Ubuntu: пакеты, время,
администраторов, SSH, UFW, fail2ban, автоматические обновления безопасности,
параметры ядра и журналирование.

Управляющий узел — **mail**. Запуск выполняется из каталога `ansible-baseline`.
[Playbook](baseline.yml) использует `hosts: all` и `become: true`: без
`--limit` изменения применяются ко всем узлам inventory, включая сам `mail`.
Для него также задано подключение по SSH.

## Где задаются настройки

| Файл или каталог | Назначение |
| --- | --- |
| [ansible.cfg](ansible.cfg) | Inventory, путь к ролям, проверка ключей SSH-серверов, формат вывода и параметры подключения |
| [baseline.yml](baseline.yml) | Запуск роли на выбранных хостах с повышением привилегий |
| [inventory/hosts.ini](inventory/hosts.ini) | Хосты, группы и пользователь подключения `ansible_user=kvg` |
| [inventory/group_vars/all.yml](inventory/group_vars/all.yml) | Общие настройки: часовой пояс, администраторы, доверенные адреса, исключения автообновлений |
| [inventory/host_vars/git.wax.su.yml](inventory/host_vars/git.wax.su.yml) | Дополнительные правила UFW для `git.wax.su` |
| [roles/baseline/defaults/main.yml](roles/baseline/defaults/main.yml) | Значения переменных по умолчанию |
| [roles/baseline/tasks/main.yml](roles/baseline/tasks/main.yml) | Порядок выполнения разделов роли и их теги |
| [roles/baseline/templates](roles/baseline/templates) | Шаблоны конфигурационных файлов |
| [roles/baseline/files](roles/baseline/files) | Python-скрипты проверки SSH |
| [roles/baseline/handlers/main.yml](roles/baseline/handlers/main.yml) | Применение sysctl и перезапуск служб после изменения конфигурации |

Обычные настройки меняйте в `inventory/group_vars/all.yml`, индивидуальные —
в `inventory/host_vars/<inventory_hostname>.yml`. Эти значения переопределяют
значения из `defaults/main.yml`. Для изменения самого поведения роли редактируйте
задачи и шаблоны.

Имя файла в `host_vars` должно совпадать с именем хоста в inventory.
Например, `git` и `git.wax.su` — разные записи: настройки из
`host_vars/git.wax.su.yml` относятся только ко второй записи.

## Что меняет роль

Разделы выполняются в порядке, приведённом ниже.

### 1. Пакеты — тег `packages`

Код: [tasks/packages.yml](roles/baseline/tasks/packages.yml).
Список пакетов: `baseline_packages` в
[defaults/main.yml](roles/baseline/defaults/main.yml).

Через APT обеспечивается наличие следующих пакетов:

```text
ca-certificates curl wget vim htop tmux git jq rsync unzip
dnsutils net-tools lsof ncdu bash-completion
chrony ufw fail2ban unattended-upgrades apt-transport-https
```

Используется `state: present`; кэш APT обновляется, если он старше 3600 секунд.
Задача не выполняет полное обновление установленных пакетов.
Настройка установленных служб выполняется в следующих разделах.

### 2. Время — тег `time`

Код: [tasks/time.yml](roles/baseline/tasks/time.yml).

- Системный часовой пояс меняется через `community.general.timezone`.
  В текущем inventory задано `baseline_timezone: Europe/Moscow`;
  значение роли по умолчанию — `Etc/UTC`.
- Служба `chrony` запускается и включается в автозагрузку.

Роль не задаёт собственные NTP-серверы и не создаёт конфигурацию chrony.
Она использует имеющуюся конфигурацию службы.

### 3. Пользователи, ключи и sudo — тег `users`

Код: [tasks/users.yml](roles/baseline/tasks/users.yml).
Настройки: список `baseline_admins` в
[inventory/group_vars/all.yml](inventory/group_vars/all.yml).

Для каждого администратора роль:

1. Создаёт или обновляет учётную запись, устанавливает shell и добавляет
   пользователя в группу `sudo`, сохраняя членство в остальных группах.
2. Добавляет указанные публичные ключи в `.ssh/authorized_keys`
   домашнего каталога пользователя.
3. При `sudo_nopasswd: true` создаёт файл
   `/etc/sudoers.d/90-<имя>` с владельцем `root:root` и правами `0440`:

   ```sudoers
   kvg ALL=(ALL:ALL) NOPASSWD: ALL
   ```

4. При `sudo_nopasswd: false` или отсутствии этого параметра удаляет
   управляемый файл `/etc/sudoers.d/90-<имя>`.

Сейчас настроен пользователь `kvg`, shell `/bin/bash` и sudo без пароля.
Публичный ключ читается из `~/.ssh/id_ed25519.pub` **пользователя, запускающего
Ansible на mail**, а затем добавляется на целевые серверы.

Перед записью sudoers-файла выполняется `visudo -cf`, после настройки —
`visudo -c` для всей конфигурации sudo; последняя проверка пропускается в
`--check`.

Ключи добавляются без удаления ранее установленных. Удаление администратора
из списка не удаляет его учётную запись, ключи или старый sudoers-файл.
Пароли пользователей роль не задаёт. Если отключаете sudo без пароля для
пользователя подключения, заранее обеспечьте ему рабочий пароль sudo
или используйте другого администратора.

#### Личные ключи, SSH-клиент и Bash

Настройки перенесены из [2.setup.sh](../2.setup.sh) и применяются к каждому
пользователю из `baseline_admins`. Код:
[tasks/user_environment.yml](roles/baseline/tasks/user_environment.yml).
Домашний каталог и основная группа берутся из результата модуля `user`,
поэтому путь не ограничен `/home/<имя>`.

| Файл в домашнем каталоге | Действие |
| --- | --- |
| `.ssh/` | Каталог пользователя с правами `0700` |
| `.ssh/id_ed25519`, `.ssh/id_ed25519.pub` | Генерация личной пары Ed25519 без passphrase, если приватного ключа ещё нет; права `0600` |
| `.ssh/config` | Управляемый блок настроек исходящих SSH-подключений; права `0600` |
| `.bashrc.baseline` | Приглашение, алиасы и история Bash; права `0644` |
| `.bashrc` | Блок подключения `.bashrc.baseline` в конце файла; права `0644` |
| `.bash_history`, `.bash_eternal_history` | Создание при отсутствии и права `0600`; существующее содержимое не очищается |

Существующий приватный ключ не заменяется. Новые ключи создаются на целевом
хосте; их приватная часть не копируется на управляющий узел. Это личные ключи
для исходящих подключений, отдельно от ключей `ssh_keys`, добавляемых в
`authorized_keys` для входа на сервер.

Настройки клиента из
[files/ssh-client.conf](roles/baseline/files/ssh-client.conf):

| Параметр | Значение |
| --- | --- |
| `StrictHostKeyChecking` | `ask` |
| `UserKnownHostsFile` | `~/.ssh/known_hosts` |
| `IdentitiesOnly`, `HashKnownHosts` | `yes` |
| `ForwardAgent`, `ForwardX11` | `no` |
| `ServerAliveInterval`, `ServerAliveCountMax` | `60` секунд, `3` |
| `ControlMaster` | `auto` |
| `ControlPath` | `~/.ssh/control-%C` |
| `ControlPersist` | `10m` |

Блок `Host *` добавляется после существующих настроек клиента. Более ранние
значения в пользовательских `Host`/`Match` сохраняют приоритет.
Это настройки SSH-клиента пользователя; параметры SSH-сервера описаны
в следующем разделе.

[files/bashrc.baseline](roles/baseline/files/bashrc.baseline) загружается
только для интерактивного Bash и содержит:

- Цветное двухстрочное приглашение с временем, пользователем, хостом и каталогом.
- Алиасы из скрипта: файловые и сетевые команды, Monit, AWS, Kubernetes,
  Terraform, обновление пакетов и поиск по истории. Их команды выполняются
  только при вызове алиаса; необходимые утилиты устанавливаются отдельно.
- `HISTSIZE=100000`, `HISTFILESIZE=200000`,
  `HISTCONTROL=ignoredups:erasedups:ignorespace`,
  `HISTIGNORE="&:[ ]*:exit:ls:ll:la:clear"` и временные метки
  `%Y-%m-%d %H:%M:%S - `.
- Дописывание и перечитывание `.bash_history` перед новым приглашением,
  дополнительную запись команды, времени и пользователя в
  `.bash_eternal_history`. Это пользовательский журнал, доступный владельцу.
- Обработчик `PROMPT_COMMAND`, сохраняющий существующие строковые или массивные
  обработчики; повторное подключение файла не добавляет его второй раз.

Перед записью Bash-файлов выполняется `bash -n`.
Из `.bashrc` и `.ssh/config` удаляются только точные исходные блоки
из `2.setup.sh`, если они обнаружены; копии этих блоков хранятся в
[setup-legacy-bashrc](roles/baseline/files/setup-legacy-bashrc) и
[setup-legacy-ssh.conf](roles/baseline/files/setup-legacy-ssh.conf).
Собственные записи вне управляемых блоков сохраняются, перед изменением
`.bashrc` и `.ssh/config` создаются резервные копии.
Если старый блок редактировался вручную, он сохраняется: его следует сверить
с новыми настройками и убрать дубли самостоятельно.

Все три возможности включены по умолчанию и управляются независимо:

| Значение роли | Переопределение в элементе `baseline_admins` |
| --- | --- |
| `baseline_user_generate_ssh_key: true` | `generate_ssh_key` |
| `baseline_user_configure_ssh_client: true` | `configure_ssh_client` |
| `baseline_user_configure_bash: true` | `configure_bash` |

Например, чтобы настроить Bash, сохранив управление личным ключом и
SSH-клиентом за пользователем:

```yaml
baseline_admins:
  - name: kvg
    shell: /bin/bash
    ssh_keys:
      - "{{ lookup('file', '~/.ssh/id_ed25519.pub') }}"
    sudo_nopasswd: true
    generate_ssh_key: false
    configure_ssh_client: false
    configure_bash: true
```

Значение `false` пропускает соответствующую настройку, но не удаляет ранее
созданные файлы или ключи. В `--check` для ещё не созданного пользователя
настройка окружения пропускается, если модуль `user` ещё не вернул домашний
каталог. Для уже работающего терминала откройте новую Bash-сессию, чтобы
загрузить обновлённые настройки.

### 4. SSH — тег `ssh`

Код: [tasks/ssh.yml](roles/baseline/tasks/ssh.yml),
[tasks/ssh_probe.yml](roles/baseline/tasks/ssh_probe.yml).
Шаблон: [sshd_baseline.conf.j2](roles/baseline/templates/sshd_baseline.conf.j2).
Файл на сервере: **`/etc/ssh/sshd_config.d/10-baseline.conf`**,
владелец `root:root`, права `0644`.

| Параметр SSH | Текущее значение | Переменная или источник |
| --- | --- | --- |
| `Port` | `22` | `baseline_ssh_port` |
| `PermitRootLogin` | `no` | `baseline_ssh_permit_root_login` |
| `PasswordAuthentication` | `no` | `baseline_ssh_password_auth` |
| `MaxAuthTries` | `3` | `baseline_ssh_max_auth_tries` |
| `PubkeyAuthentication` | `yes` | Шаблон |
| `KbdInteractiveAuthentication` | `no` | Шаблон |
| `PermitEmptyPasswords` | `no` | Шаблон |
| `LoginGraceTime` | `30` секунд | Шаблон |
| `X11Forwarding` | `no` | Шаблон |
| `ClientAliveInterval` | `300` секунд | Шаблон |
| `ClientAliveCountMax` | `2` | Шаблон |

Перед изменениями роль проверяет отдельное подключение по ключу с `mail`
под `ansible_user`. Проверка не использует уже открытое multiplex-соединение,
пароль или интерактивную аутентификацию; ключ сервера должен быть известен
управляющему пользователю.

Новая конфигурация сначала создаётся во временном каталоге на целевом сервере.
[validate_sshd.py](roles/baseline/files/validate_sshd.py) проверяет её в копии
полной конфигурации с учётом `Include`: выполняет `sshd -t` и сверяет
эффективные глобальные настройки аутентификации через `sshd -T`.
Основной `/etc/ssh/sshd_config` должен включать управляемый файл.

При реальном применении роль сохраняет предыдущее содержимое и права файла,
устанавливает новый вариант, выполняет `sshd -t`, перечитывает конфигурацию
службы `ssh` при изменении и повторяет отдельную проверку входа по ключу.
При ошибке выполняются задачи восстановления прежнего файла и его прав;
если файла раньше не было, новый файл удаляется. Временный каталог очищается
в блоке `always`.

Порт подключения должен уже совпадать с `baseline_ssh_port`: миграция на
другой порт требует отдельной процедуры. Проверка `sshd -T` не перебирает
все варианты условий `Match`; проверка подключения подтверждает доступ
для конкретного пользователя и адреса управляющего узла.

### 5. Межсетевой экран UFW — тег `ufw`

Код: [tasks/ufw.yml](roles/baseline/tasks/ufw.yml).
Роль меняет правила и политики UFW через `community.general.ufw`.

Порядок действий:

1. Для каждого IP-адреса или сети из `baseline_ssh_allowed` разрешает
   **весь входящий трафик на любые порты и по всем протоколам**.
   Новые правила вставляются в начало списка UFW.
2. Добавляет индивидуальные правила из `baseline_ufw_rules`.
3. Устанавливает политики по умолчанию: входящий трафик — `deny`,
   исходящий — `allow`.
4. Включает UFW, если `baseline_ufw_enable: true` — это значение по умолчанию.

Список доверенных адресов задаётся в
[inventory/group_vars/all.yml](inventory/group_vars/all.yml).
Имя `baseline_ssh_allowed` сохранено для совместимости: оно больше не означает
ограничение разрешённого трафика только SSH.

Для `git.wax.su` в
[host_vars/git.wax.su.yml](inventory/host_vars/git.wax.su.yml)
дополнительно открыты TCP-порты `80` и `443` для любых источников.
Правило для отдельного хоста может содержать поля:

| Поле | Назначение | Если не задано |
| --- | --- | --- |
| `port` | Порт назначения | Обязательное поле |
| `proto` | Протокол | `tcp` |
| `src` | IP-адрес или сеть источника | `any` |
| `rule` | Действие UFW | `allow` |

Роль добавляет правила без удаления прежних. Удаление адреса из переменной
не отзывает уже созданное разрешение в UFW.
`baseline_ufw_enable: false` только пропускает включение UFW:
задачи правил и политик продолжают выполняться, уже работающий UFW не выключается.

### 6. Fail2ban — тег `fail2ban`

Код: [tasks/fail2ban.yml](roles/baseline/tasks/fail2ban.yml).
Шаблон: [fail2ban-sshd.local.j2](roles/baseline/templates/fail2ban-sshd.local.j2).
Файл на сервере: **`/etc/fail2ban/jail.d/sshd.local`**, права `0644`.

Включается jail `sshd` с чтением событий через `backend = systemd`
и блокировками через `banaction = ufw`.

| Переменная | Текущее значение |
| --- | --- |
| `baseline_fail2ban_bantime` | `1h` — длительность блокировки |
| `baseline_fail2ban_findtime` | `10m` — окно подсчёта неудачных попыток |
| `baseline_fail2ban_maxretry` | `5` — порог попыток |
| `baseline_fail2ban_ignoreip` | `127.0.0.1/8`, `::1` и все адреса из `baseline_ssh_allowed` |
| `baseline_ssh_port` | `22` — порт защищаемого SSH |

Служба `fail2ban` запускается и включается в автозагрузку.
При изменении файла конфигурации handler перезапускает службу.
Параметры `[DEFAULT]` в этом файле могут влиять и на другие jail,
если те не переопределяют соответствующие значения.

### 7. Автоматические обновления — тег `unattended`

Код: [tasks/unattended.yml](roles/baseline/tasks/unattended.yml).
Шаблон: [52-baseline-unattended.j2](roles/baseline/templates/52-baseline-unattended.j2).

| Файл на сервере | Что записывается |
| --- | --- |
| `/etc/apt/apt.conf.d/52baseline-unattended` | Разрешённые источники обновлений безопасности, исключённые пакеты, очистка зависимостей и политика перезагрузки |
| `/etc/apt/apt.conf.d/20auto-upgrades` | Обновление списков пакетов и запуск unattended-upgrades с интервалом 1 день, autoclean — 7 дней |

Оба файла имеют права `0644`. Перед заданием разрешённых источников шаблон
очищает ранее накопленные списки `Allowed-Origins` и `Origins-Pattern`.
Разрешены:

```text
${distro_id}:${distro_codename}-security
${distro_id}ESMApps:${distro_codename}-apps-security
${distro_id}ESM:${distro_codename}-infra-security
```

Это список допустимых источников для unattended-upgrades; подключение
репозиториев и активацию Ubuntu Pro/ESM роль не выполняет.

В текущем `baseline_unattended_blacklist` указаны `gitlab-ce`, `gitlab-ee`,
`ansible` и `ansible-core`. Эти пакеты исключены из автоматического обновления.
Включено удаление неиспользуемых пакетов ядер и зависимостей.
`baseline_unattended_auto_reboot: false` отключает автоматическую перезагрузку
со стороны unattended-upgrades.

На реальном запуске после записи файлов выполняется `apt-config dump`.
Роль проверяет, что итоговый список источников содержит именно три указанных
значения, а `Origins-Pattern` пуст. Если другая конфигурация меняет эту политику,
выполнение останавливается с ошибкой. В `--check` эта проверка пропускается.

### 8. Параметры ядра и journald — тег `system`

Код: [tasks/system.yml](roles/baseline/tasks/system.yml).

**Параметры ядра.** Шаблон
[90-baseline-sysctl.conf.j2](roles/baseline/templates/90-baseline-sysctl.conf.j2)
записывается в **`/etc/sysctl.d/90-baseline.conf`** с правами `0644`.

| Параметры | Значение |
| --- | --- |
| `net.ipv4.tcp_syncookies` | `1` |
| `net.ipv4.conf.{all,default}.rp_filter` | `2` |
| `net.ipv4.conf.{all,default,*}.accept_redirects` | `0` |
| `net.ipv6.conf.{all,default,*}.accept_redirects` | `0` |
| `net.ipv4.conf.{all,default,*}.send_redirects` | `0` |
| `net.ipv4.conf.all.accept_source_route` | `0` |
| `net.ipv4.icmp_echo_ignore_broadcasts` | `1` |
| `net.ipv4.conf.all.log_martians` | `1` |
| `kernel.kptr_restrict`, `kernel.dmesg_restrict` | `2`, `1` соответственно |
| `fs.protected_hardlinks`, `fs.protected_symlinks` | `1` |

Фигурные скобки в таблице сокращают несколько отдельных строк шаблона;
`*` обозначает шаблон для интерфейсов.
Эти параметры заданы непосредственно в шаблоне, отдельных переменных роли
для них нет. При изменении файла handler выполняет:

```bash
/usr/lib/systemd/systemd-sysctl /etc/sysctl.d/90-baseline.conf
```

**Журналирование.** Создаётся каталог `/etc/systemd/journald.conf.d`
с правами `0755` и файл **`/etc/systemd/journald.conf.d/10-baseline.conf`**
с правами `0644`:

```ini
[Journal]
SystemMaxUse=500M
```

Размер задаётся переменной `baseline_journald_max_use`.
При изменении файла handler перезапускает `systemd-journald`.
Режим хранения журнала `Storage` роль не задаёт.

## Когда применяются изменения и перезапускаются службы

| Служба или подсистема | Действие |
| --- | --- |
| `chrony` | Запуск при необходимости и включение в автозагрузку |
| `ssh` | Перечитывание конфигурации сразу после её изменения и проверки; также при восстановлении после ошибки |
| UFW | Правила и политики применяются задачами; затем включение при `baseline_ufw_enable: true` |
| `fail2ban` | Запуск и автозагрузка; перезапуск handler при изменении конфигурации |
| sysctl | Handler применяет файл `90-baseline.conf` при его изменении |
| `systemd-journald` | Перезапуск handler при изменении конфигурации |
| APT | Запись настроек периодических обновлений и проверка итоговой конфигурации; немедленный запуск обновления пакетов не вызывается |

Handlers обычно выполняются в конце play. Перечитывание SSH выполняется
непосредственно внутри SSH-задач. Восстановление при ошибке реализовано
для управляемого SSH-файла; общего отката всех изменений роли нет.

## Требования перед запуском

- Управляющий узел `mail`: Linux, Python 3, Ansible и SSH-клиент.
  Код ранее проверялся статически с синтаксисом ansible-core 2.19.
- Целевые хосты: Ubuntu, systemd, Python 3, работающий OpenSSH-сервер
  и sudo. SSH-конфигурация должна включать
  `/etc/ssh/sshd_config.d/10-baseline.conf` напрямую или через маску.
- Коллекции `community.general` и `ansible.posix`.
- Рабочий доступ по ключу под `ansible_user` и возможность выполнять sudo.
  При запросе пароля sudo добавляйте `--ask-become-pass`.
- Проверенные ключи серверов в `known_hosts` управляющего пользователя
  и доступный приватный ключ либо SSH-agent для подключения.
- Публичный ключ `~/.ssh/id_ed25519.pub` на управляющем узле для текущей
  настройки `baseline_admins`.
- Адрес, с которого сервер видит подключение управляющего узла,
  должен входить в `baseline_ssh_allowed`, чтобы доступ сохранялся после
  включения UFW.

Статические проверки не заменяют пробный запуск на используемой версии Ubuntu.

## Как запускать

Все команды выполняются на `mail` из каталога `ansible-baseline`.

Установите коллекции и проверьте список хостов, задач и синтаксис:

```bash
ansible-galaxy collection install community.general ansible.posix
ansible-inventory --graph
ansible-playbook baseline.yml --syntax-check
ansible-playbook baseline.yml --list-hosts --limit stage.wax.su
ansible-playbook baseline.yml --list-tasks --limit stage.wax.su
```

Сначала проверьте изменения на одном хосте, затем примените их:

```bash
ansible-playbook baseline.yml --limit stage.wax.su --check --diff
ansible-playbook baseline.yml --limit stage.wax.su --diff
```

После проверки результата переходите к следующим хостам по одному:

```bash
ansible-playbook baseline.yml --limit git.wax.su --check --diff
ansible-playbook baseline.yml --limit git.wax.su --diff
```

Для отдельных разделов после первоначальной настройки используйте теги:

```bash
ansible-playbook baseline.yml --limit stage.wax.su --tags ufw --check --diff
ansible-playbook baseline.yml --limit stage.wax.su --tags ufw --diff
ansible-playbook baseline.yml --limit stage.wax.su --tags users --check --diff
ansible-playbook baseline.yml --limit stage.wax.su --tags users --diff
ansible-playbook baseline.yml --limit stage.wax.su --tags users,ssh,ufw,fail2ban --diff
```

Доступные теги: `packages,time,users,ssh,ufw,fail2ban,unattended,system`.
Если меняете доверенные адреса, учтите, что список используется и UFW,
и fail2ban; для обновления обоих разделов нужны теги `ufw,fail2ban`.
Ранее добавленные разрешения UFW при этом автоматически не удаляются.

## Что учитывать при проверке и повторном запуске

`--check` не создаёт будущую систему целиком: установка пакетов и создание
пользователей только прогнозируются. На новом сервере последующая проверка SSH
может завершиться ошибкой до появления нужных пакетов или администратора.
Для первого запуска заранее подготовьте доступ администратора.

Некоторые действия в SSH-разделе выполняются даже с `--check`:
отдельное подключение по ключу, создание временных файлов, проверка кандидата
и очистка временного каталога. Рабочий SSH-файл в этом режиме не заменяется.
Вывод `--diff` зависит от модуля; рендеринг временного SSH-кандидата и сохранение
его предыдущего содержимого выполняются с `diff: false`.

Ручные изменения полностью управляемых файлов перезаписываются при следующем
применении; в `.bashrc` и `.ssh/config` роль управляет только своими блоками.
Для постоянных изменений используйте переменные, задачи или шаблоны роли.
Удаление пользователя, ключа или правила из списка переменных само по себе
не удаляет ранее созданный объект на сервере, кроме явно описанного удаления
управляемого sudoers-файла при отключении `sudo_nopasswd`.

Проверить результат на целевом хосте можно командами:

```bash
timedatectl status
systemctl is-active chrony ssh fail2ban systemd-journald
id kvg
sudo visudo -c
sudo sshd -t
sudo ufw status verbose
sudo fail2ban-client status sshd
apt-config dump
sysctl net.ipv4.tcp_syncookies net.ipv4.conf.all.accept_redirects kernel.kptr_restrict
journalctl --disk-usage
```
