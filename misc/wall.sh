#!/bin/bash
#
# Send "wall" message on login.
# Place in /etc/profile.d/
#

if (( SHLVL == 1 )); then
    if [[ -z "$SSH_CLIENT" ]]; then
        MESSAGE="        ATTENTION! $USER logged in from console"
        IP="console"
    else
        IP=${SSH_CLIENT%%\ *}
        MESSAGE="        ATTENTION! $USER logged in from $IP"
    fi

    if [[ -f ${HOME}/.white_ip ]]; then
        MUTE=$(grep -Fcx "$IP" ~/.white_ip)
    else
        MUTE=0
    fi

    if (( ! MUTE )); then
        wall "$MESSAGE"
    fi
fi

## EOF ##
