#!/bin/bash

# Utility for managing Neovim plugins as git submodules.
#
# The script can be called from anywhere and has a simple CRUD-style interface:
# ADD/CREATE submodules by cloning from GitHub, GitLab, etc., UPDATE by pulling
# changes from the origin of each remote, GET/READ from your own remote, and DELETE
# local submodules by removing the relevant files and clearing Git's cache and index.
# In addition, the script facilitates syncing with your own remote.


help_msg="Usage: plugnvim.sh [OPTIONS] [PATH]

ARGS:
    <URL>       The address of a plugin repository
    <FILE>      The path to a file

OPTIONS:
    -h, --help                  Display this message
    -a, --add <URL/PATH>        Add submodule(s) at URL or contained in file at PATH
    -u, --update [URL]          Update plugin with origin at URL; no ARG to update everything
    -g, --get <URL>             Get submodules from remote plugin repo at URL
    -d, --delete <URL>          Delete submodule with origin URL
    -s, --sync                  Sync with remote by pushing changes
    -r, --restore               Restore state of submodules, discard unstaged changes
    -o, --opt                   Install plugins into /opt/
    -or, -ro                    Remove plugin from /opt/

Install a single plugin by passing the address of a repository, or several by
passing the path to a .txt file containing URLs (one per line). For example,

plugnvim.sh [-a/--add] https://<domain>/<author>/<plugin>
plugnvim.sh [-a/--add] https://<domain>/<author>/<plugin>/<branch>

will install <plugin> into:

\$Home/.local/share/nvim/site/pack/plugin/start/
"


#=== global constants & variables =======================================================
XDG_DATA_HOME="$HOME/.local/share"
NVIM_PLUGIN_PATH="$XDG_DATA_HOME/nvim/site/pack/plugins"

# keep track of execution dir in order to access file with plugins, if necessary
ORIGIN=$PWD

# defaults
METHOD=ADD
TARGET_DIR=start


#=== helper functions ===================================================================
handle_options() {
    while (( $# )); do
        case $1 in
            -h | --help)
                printf "%s" "$help_msg"
                exit
                ;;
            -a | --add)
                METHOD=ADD
                shift
                ;;
            -d | --delete)
                METHOD=DELETE
                shift
                ;;
            -g | --get)
                METHOD=GET
                shift
                ;;
            -u | --update)
                METHOD=UPDATE
                shift
                ;;
            -s | --sync)
                METHOD=SYNC
                shift
                ;;
            -r | --restore)
                METHOD=RESTORE
                shift
                ;;
            -o | --opt)
                TARGET_DIR=opt
                shift
                ;;
            -ro | -or)
                METHOD=REMOVE
                TARGET_DIR=opt
                shift
                ;;
            *)
                POSITIONAL_ARGS+=("$1") # save positional args
                shift
                ;;
        esac
    done
    set -- "${POSITIONAL_ARGS[@]}" # restore positional args
}

checkout_nvim_dir() {
    # cd into plugin directory, create directory structure if necessary
    # args: none
    # globals: NVIM_PLUGIN_PATH (str), TARGET_DIR (str)

    if [ -d "$NVIM_PLUGIN_PATH" ]; then
        cd "$NVIM_PLUGIN_PATH" || return
    else
        mkdir -p "$NVIM_PLUGIN_PATH/opt"
        mkdir "$NVIM_PLUGIN_PATH/start"
        cd "$NVIM_PLUGIN_PATH"  || return
    fi
}

install_single_plugin() {
    # extract plugin name and repo branch; add submodule to target directory
    # args: repo (str)
    # globals: NVIM_PLUGIN_PATH (str), TARGET_DIR (str)

    local repo
    local plugin
    local branch

    repo=$1
    plugin=$(echo "$repo" | cut -d/ -f5-)

    # check if particular repo branch is specified
    if [[ $plugin =~ "/tree/" ]]; then
        branch=$(echo "$plugin" | cut -d/ -f3)
        plugin=$(echo "$plugin" | cut -d/ -f1)
        repo=${repo%/*}
        repo=${repo%/*}
        git submodule add -b "$branch" -- "$repo" "$TARGET_DIR/$plugin"
    else
        git submodule add "$repo" "$TARGET_DIR/$plugin"
    fi
}

update_single_plugin() {
    # extract plugin name, get target_dir; add submodule to target directory
    # args: repo (str), target_dir (str, optional, defaults to TARGET_DIR)
    # globals: NVIM_PLUGIN_PATH (str), TARGET_DIR (str)

    local repo
    local target_dir
    local plugin

    repo=$1
    plugin=$(echo "$repo" | cut -d/ -f5-)

    target_dir=$2

    git submodule update --remote "$target_dir/$plugin"
}



#=== main ===============================================================================
handle_options "$@"

if [[ $# -eq 0 ]]; then
    printf "%s" "$help_msg"
#
# GET
#
elif [[ $METHOD == "GET" ]]; then
    mkdir -p "$XDG_DATA_HOME/nvim/site/pack" && cd "$XDG_DATA_HOME/nvim/site/pack" || return
    git clone --depth=10 --recursive "$POSITIONAL_ARGS plugins"
    git submodule update --checkout
#
# ADD
#
elif [[ $METHOD == "ADD" ]]; then
    checkout_nvim_dir

    if [[ ! -d ".git" ]]; then
        git init
    fi

    # clone all repos contained in file
    if [[ $1 =~ [a-z].txt ]]; then
        repos=$(cat "$ORIGIN/$1")
        for repo in $repos; do
            install_single_plugin "$repo"
        done

        git submodule init

        git add .
        git commit -m "add submodules from repositories:" -m "${repos[@]}"
    # clone single repo given by argument
    elif [[ -n $POSITIONAL_ARGS ]]; then
        repo=$POSITIONAL_ARGS
        install_single_plugin "$repo"

        git add .
        git commit -m "add submodule from repository:" -m "$repo"
    else
        printf "%s" "$help_msg"
    fi
#
# UPDATE
#
elif [[ $METHOD == "UPDATE" ]]; then
    checkout_nvim_dir

    if [[ -n $POSITIONAL_ARGS ]]; then
        update_single_plugin "$POSITIONAL_ARGS" "${3:-$TARGET_DIR}"
    else
        git submodule update --remote
    fi

    git_diff=$(git diff --name-status | cut -f2)
    git add .
    git commit -m "update submodules:" -m "$git_diff"
#
# DELETE
#
elif [[ $METHOD == "DELETE" ]]; then
    checkout_nvim_dir

    plugin="$(echo "$POSITIONAL_ARGS" | cut -d/ -f5)"

    # delete submodule
    rm -r $TARGET_DIR/${plugin%/}

    # remove submodule from index (check for trailing slash)
    git config -f .gitmodules --remove-section submodule.$TARGET_DIR/${plugin%/}
    rm -rf .git/modules/$TARGET_DIR/${plugin%/}

    git add .
    git commit -m "remove submodule:" -m "$plugin"
#
# SYNC
#
elif [[ $METHOD == "SYNC" ]]; then
    checkout_nvim_dir
    git push
#
# RESTORE
#
elif [[ $METHOD == "RESTORE" ]]; then
    checkout_nvim_dir
    git submodule deinit -f .
    git submodule update --init
fi
