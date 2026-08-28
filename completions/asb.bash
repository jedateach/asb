# bash completion for asb
_asb() {
    local cur prev words cword
    if type -t _init_completion >/dev/null; then
        _init_completion || return
    else
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    fi

    local config_root="${XDG_CONFIG_HOME:-$HOME/.config}/asb"
    local commands="create delete use list add remove recover launch lockdown doctor help"

    _asb_sandboxes() {
        local d
        for d in "$config_root"/*/; do
            [[ -d "$d" ]] && basename "$d"
        done
    }
    _asb_agents() {
        [[ -f "$config_root/agents.conf" ]] &&
            sed -n 's/^\([A-Za-z0-9_-]\+\)=.*/\1/p' "$config_root/agents.conf"
    }

    case "$prev" in
        -s|--sandbox)
            COMPREPLY=($(compgen -W "$(_asb_sandboxes)" -- "$cur"))
            return
            ;;
        --agent)
            COMPREPLY=($(compgen -W "$(_asb_agents)" -- "$cur"))
            return
            ;;
    esac

    # Find the subcommand (first non-option word after 'asb')
    local i cmd=""
    for ((i = 1; i < cword; i++)); do
        case "${words[i]}" in
            -s|--sandbox) ((i++)) ;;
            -*) ;;
            *) cmd="${words[i]}"; break ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        return
    fi

    case "$cmd" in
        delete|use|list)
            COMPREPLY=($(compgen -W "$(_asb_sandboxes)" -- "$cur"))
            ;;
        launch)
            COMPREPLY=($(compgen -W "$(_asb_sandboxes) $(_asb_agents)" -- "$cur"))
            ;;
        add|remove)
            COMPREPLY=($(compgen -d -- "$cur"))
            ;;
        create)
            COMPREPLY=($(compgen -W "--agent" -- "$cur"))
            ;;
    esac
}
complete -F _asb asb
