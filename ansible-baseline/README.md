# Baseline для серверов wax.su

Роль настраивает пакеты, время, администраторов, SSH, UFW, fail2ban,
автообновления безопасности, sysctl и journald.

Список `baseline_ssh_allowed` в `inventory/group_vars/all.yml` задаёт доверенные
IP-адреса и сети: UFW разрешает от них весь входящий трафик на любые порты
и по всем протоколам. Новые разрешающие правила вставляются в начало списка
UFW. Имя переменной сохранено для совместимости; этот же список используется
в исключениях fail2ban.

## Требования

- Управляющий узел Linux с Python 3 и Ansible; код проверен статически с
  синтаксисом ansible-core 2.19.
- Целевые хосты Ubuntu с systemd, OpenSSH и Python 3.
- Коллекции community.general и ansible.posix.
- Существующий доступ по ключу под ansible_user и sudo для запуска роли.
- Проверенный ключ сервера в known_hosts управляющего пользователя.
- Указанные проверки не заменяют интеграционный прогон на вашей версии Ubuntu.

## Запуск роли

На управляющем узле `mail`, из каталога `ansible-baseline`:

    ansible-galaxy collection install community.general ansible.posix
    ansible-playbook baseline.yml --syntax-check
    ansible-playbook baseline.yml --limit stage.wax.su --check --diff
    ansible-playbook baseline.yml --limit stage.wax.su --diff

После проверки результата применяйте роль к остальным хостам по одному:

    ansible-playbook baseline.yml --limit git.wax.su --check --diff
    ansible-playbook baseline.yml --limit git.wax.su --diff

Доступны теги packages,time,users,ssh,ufw,fail2ban,unattended,system.
Для запуска отдельных частей роли после первоначальной настройки:

    ansible-playbook baseline.yml --limit stage.wax.su --tags users,ssh,ufw,unattended,system --diff

Первичная установка пакетов и создание пользователей не симулируют будущую
систему полностью в --check: на новом сервере проверка ключевого доступа
может остановиться до реального создания администратора. Сначала настройте
доступ администратора отдельным bootstrap-процессом.

Если sudo требует пароль, добавьте --ask-become-pass. При отключении
sudo_nopasswd у пользователя, которым запускается Ansible, заранее обеспечьте
ему рабочий пароль sudo или используйте другого администратора.

## Ограничения

Ключи администраторов добавляются без автоматического отзыва старых.
UFW-правила добавляются без удаления прежних; false в baseline_ufw_enable
пропускает включение, но не выключает уже работающий firewall.
