#!/bin/bash

# Utility for managing Neovim plugins as git submodules.
#
# The script has a simple CRUD-style interface: CREATE local submodules by cloning
# from GitHub, GitLab, etc., DELETE local submodules by removing the relevant files and
# clearing Git's cache and index, GET remote submodules by cloning from your own remote,
# UPDATE local submodules by pulling changes from the origin of each submodule, and PUSH
# changes to your own remote.
#
# The script will automatically update your local Git repository containing the
# submodules by staging and committing any changes. Pushing the changes to your remote 
# must be done separately.

help_msg="Usage: plugnvim.sh [OPTIONS] [<repository/file>]

Options:
    -h, --help      Display this message
    -c, --create    Create submodule(s)
    -u, --update    Update submodule(s)
    -g, --get       Get submodules from remote
    -d, --delete    Delete submodule
    -p, --push      Push submodule changes to remote
    -o, --opt       Install plugins into /opt/
    -or, -ro        Remove plugin from /opt/

Install a single plugin by passing the address of the plugin repository,
or several plugins by passing the name of a .txt file containing repo
addresses, (one per line). For example,

plugnvim.sh [-a/--add] https://<domain>/<author>/<plugin>
plugnvim.sh [-a/--add] https://<domain>/<author>/<plugin>/<branch>

will install <plugin> into:

\$Home/.local/share/nvim/site/pack/plugin/start/

Run the script with the -o or --opt flag to install them in ../../plugin/opt/,
which contains optional plugins that are not automatically loaded on Neovim startup.
"


#=== global constants & variables =======================================================
XDG_DATA_HOME="$HOME/.local/share"
NVIM_PLUGIN_PATH="$XDG_DATA_HOME/nvim/site/pack/plugins"

# keep track of execution dir in order to access file with plugins, if necessary
ORIGIN=$PWD

# defaults
METHOD=CREATE
TARGET_DIR=start


#=== helper functions ===================================================================
handle_options() {
    while (( $# )); do
        case $1 in
            -h | --help)
                printf "%s" "$help_msg"
                exit
                ;;
            -c | --create)
                METHOD=CREATE
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
            -p | --push)
                METHOD=PUSH
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
        cd $NVIM_PLUGIN_PATH
    else
        mkdir -p "$NVIM_PLUGIN_PATH/opt"
        mkdir "$NVIM_PLUGIN_PATH/start"
        cd $NVIM_PLUGIN_PATH 
    fi
}

install_single_plugin() {
    # extract plugin name and repo branch; add submodule to target directory
    # args: repo (str)
    # globals: NVIM_PLUGIN_PATH (str), TARGET_DIR (str)

    local repo=$1
    local plugin=$(echo $repo | cut -d/ -f5-)

    # check if particular repo branch is specified
    if [[ $plugin =~ "/tree/" ]]; then
        local branch=$(echo $plugin | cut -d/ -f3)
        plugin=$(echo $plugin | cut -d/ -f1)
        repo=${repo%/*}
        repo=${repo%/*}
        git submodule add -b $branch -- "$repo" $TARGET_DIR/$plugin
    else
        git submodule add "$repo" $TARGET_DIR/$plugin
    fi
}


#=== main ===============================================================================
handle_options "$@"

#
# GET
#
if [[ $METHOD == "GET" ]]; then
    mkdir -p "$XDG_DATA_HOME/nvim/site/pack" && cd "$XDG_DATA_HOME/nvim/site/pack"
    git clone --recursive $POSITIONAL_ARGS plugins
    git submodule update --checkout
#
# CREATE
#
elif [[ $METHOD == "CREATE" ]]; then
    checkout_nvim_dir

    if [[ ! -d ".git" ]]; then
        git init
    fi

    # clone all repos contained in file
    if [[ $1 =~ [a-z].txt ]]; then
        repos=$(cat "$ORIGIN/$1")
        for repo in $repos; do
            install_single_plugin $repo
        done

        git submodule init

        git add .
        git commit -m "create submodules from repositories:" -m "${repos[@]}"
    # clone single repo given by argument
    else
        repo=$POSITIONAL_ARGS
        install_single_plugin $repo

        git add .
        git commit -m "create submodule from repository:" -m "$repo"
    fi
#
# UPDATE
#
elif [[ $METHOD == "UPDATE" ]]; then
    checkout_nvim_dir
    git submodule update --remote

    git_diff=$(git diff --name-status | cut -f2)
    git add .
    git commit -m "update submodules:" -m "$git_diff"
#
# PUSH
#
elif [[ $METHOD == "PUSH" ]]; then
    checkout_nvim_dir
    git push
#
# DELETE
#
else
    checkout_nvim_dir

    plugin="$(echo $POSITIONAL_ARGS | cut -d/ -f5)"

    # delete submodule
    rm -r $TARGET_DIR/${plugin%/}

    # remove submodule form index (check for trailing slash)
    git config -f .gitmodules --remove-section submodule.$TARGET_DIR/${plugin%/}
    rm -rf .git/modules/$TARGET_DIR/${plugin%/}

    git add .
    git commit -m "remove submodule:" -m "$plugin"
fi
