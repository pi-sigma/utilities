#!/bin/bash

# The script facilitates running Django tests from the command line with
# a simple interface to find and run Django test methods, classes, modules and
# packages. It uses fzf, fd, and ripgrep for searching, so these need to
# be installed. The script supports re-running previous tests via env variables
# which need to be accessible from the parent shell, hence the script must be
# sourced (from the directory where your manage.py file is located); remaining
# variables are unset to prevent cluttering the environment of the parent shell.


help_msg="Usage: . djtest.sh [OPTIONS] [method/class] [Django options]

Options:
    -h, --help      Display this message
    -r, --repeat    Repeat previous test
    -c, --clear     Clear Django options from previous run

Arguments:
    [method/class]    Method should follow <test_foo_bar>. Class should be
                      <FooBarTest> or <FooBarTests>, although <TestFooBar> and
                      <TestsFooBar> are supported as well
    [Django options]  --keepd etc. are passed along to the Django test runner

If neither OPTIONS nor method/class are provided, the script starts an interactive
fuzzy search over the contents of the current working directory (after changing to the
src/ or app/ directory, if applicable) and execute the tests in the specified module or
package. Provide the -r flag to run the previous test together with any Django options
specified on the last run.
"


get_first_arg() {
  echo "$1" | cut -d' ' -f1
}

#===FUNCTION====================================================================
# Handle options and arguments
# Globals:
#   help
#   repeat
#   clear_options
# Arguments:
#   Options to run the script with
#===============================================================================
handle_options() {
  while (( $# )); do
    case $1 in
      -h | --help)
      help=true
      ;;
      -r | --repeat)
      repeat=true
    esac
    shift
  done
}

#===FUNCTION====================================================================
# Get file paths
# Globals:
#   None
# Arguments:
#   method  (string)
# Outputs:
#   file_paths
# Details:
#   Retrieve all paths of files where method name is found
#===============================================================================
get_file_paths() {
  local method=$*
  local file_paths

  IFS=$'\n' file_paths=$(rg -w "$method" | rg -o '^[^:]+' | uniq)
  echo "${file_paths}"
}

#===FUNCTION====================================================================
# Display file paths
# Globals:
#   None
# Arguments:
#   None
# Details:
#   Displays paths of files in which test method/class is found
#===============================================================================
show_file_paths() {
  local elem
  local ITER

  echo $'The name of the test method/class was found in multiple files:\n'

  ITER=1
  for elem in "$@"; do
    echo "(${ITER}) ${elem}"
    ((ITER++))
  done
}

#===FUNCTION====================================================================
# Get class names
# Globals:
#   None
# Arguments:
#   file path   (string)
#   method      (string)
# Outputs:
#   name(s) of test class/classes (FooBarTest)
# Details:
#   Finds start lines by reading file in reverse, stopping at each occurrence
#   of $method; finds class definition by reading file in reverse, starting at
#   each $start_line; extracts and outputs class name
#===============================================================================
get_class_names() {
  local file_path=$1
  local method=$2
  local start_lines
  local class_def
  local class_name

  start_lines=("$(tac "$file_path" | rg -w -n "$method" | cut -f1 -d:)")

  for start_line in ${start_lines[@]}; do
    class_def=$(tac "$file_path" | sed -n ''"$start_line"',$p' | rg -w -m 1 "^class [a-zA-Z]+")
    class_name="${class_def%%(*}"
    class_name="${class_name:6}"
    echo "$class_name"
  done
}

#===FUNCTION====================================================================
# Display class names
# Globals:
#   None
# Arguments:
#   class names (array)
#   file_path   (string)
# Details:
#   Displays names of classes in which test is found
#===============================================================================
show_class_names() {
  local class_names=( "${@:1:$# - 1}" )
  local file_path="${!#}"
  local elem
  local ITER

  echo $'The test method was found in multiple classes:\n'

  ITER=1
  for elem in "${class_names[@]}"; do
    echo "(${ITER}) $file_path: ${elem}"
    ((ITER++))
  done
}

#===FUNCTION====================================================================
# Make dotted path
# Globals:
#   None
# Arguments:
#   file_path   (string)
#   class_name  (string, optional)
#   method      (string, optional)
# Returns:
#   a dotted path (foo.bar.BazTest.test_example)
# Details:
#   Strips extension or traling slash from file_path and replaces '/' with '.'.
#   Attaches class_name and method, if applicable.
#===============================================================================
make_dotted_path() {
  local arg=$1
  local path
  local dotted_path

  if [[ $arg == *.py ]]; then
    path=${arg::-3}
  else
    path=${arg::-1}
  fi

  dotted_path=${path//\//.}
  [ "$2" ] && dotted_path+=".$2"
  [ "$3" ] && dotted_path+=".$3"
  echo "$dotted_path"
}

#===FUNCTION====================================================================
# Run test
# Globals:
#   previous_django_test    (string)
#   django_test_options     (string)
# Arguments:
#   dotted_path (string)
# Outputs:
#   Writes dotted_path to stdout
# Details:
#   Saves test command and django test options in env variables for re-running
#   the script with the -r flag before executing the test
#===============================================================================
run_test() {
  previous_django_test="python manage.py test $1"
  echo "$1"
  echo
  [ "$1" != "" ] && eval "$previous_django_test" "$django_test_options"  && echo ">>> $1 <<<"
}

cleanup() {
  unset class_name class_names clear_options
  unset dotted_path
  unset file_path file_paths
  unset help help_msg
  unset path
  unset repeat
  unset src_dir
  unset target
  unset user_choice
}

user_interrupt() {
   cleanup
   unset repeat clear_options
}

#===MAIN========================================================================
# 1. Change to src/ or app/ directory, if applicable
# 2. Handle options and arguments
# 3. Display help, if applicable
# 4. Re-rerun previous test, if applicable (possibly override test options)
# 5. Run test
#   a) (method): get file paths where method name is found; check for multiple
#      paths and let user choose; get names of classes; check for multiple
#      classes, let user choose; make dotted path, collect test options, run test
#   b) (class): same as a), except the class name is given
#   c) (module/package): same as a), except the first steps are skipped
# 6. Change back to $PWD, if applicable
# 7. Clean up
#===============================================================================
main() {
  [ -d src ] && cd src/ && src_dir=true
  [ -d app ] && cd app/ && src_dir=true

  handle_options "$@"

  if [ "$help" = true ]; then
    printf "%s" "$help_msg"
  elif [ "$repeat" = true ]; then
    echo "Running previous test..."

    if [ "$clear_options" = true ]; then
        django_test_options=${@:4}
    fi

    eval "$previous_django_test"  "$django_test_options"
  else
    target=("${@:1}")
    #
    # method
    #
    if [[ "$target" =~ test[a-z_0-9]+$ ]]; then
      method=$(get_first_arg "$@")

      file_paths=($(get_file_paths "$method"))

      if [[ ${#file_paths[@]} -gt 1 ]]; then
        show_file_paths "${file_paths[@]}"
        read -rp $'\nSelect a file path: ' user_choice
        file_path="${file_paths[$user_choice - 1]}"
      else
        file_path="${file_paths[0]}"
      fi

      class_names=($(get_class_names "$file_path" "$method"))

      if [[ ${#class_names[@]} -gt 1 ]]; then
        show_class_names "${class_names[@]}" "$file_path"
        read -rp $'\nSelect a test class: ' user_choice
        class_name="${class_names[$user_choice - 1]}"
      else
        class_name="${class_names[0]}"
      fi

      dotted_path=$(make_dotted_path "$file_path" "$class_name" "$method")

      django_test_options="${*:2}"
    #
    # class
    #
    elif [[ "$target" =~ [\'Test\']?[A-Za-z][Test][s]?$ ]] || [[ "$target" =~ Test[A-Za-zT]+$ ]]; then
      class_name=$(get_first_arg "$@")

      file_paths=($(get_file_paths "$class_name"))

      if [[ ${#file_paths[@]} -gt 1 ]]; then
        show_file_paths "${file_paths[@]}"
        read -rp $'\nSelect a file path: ' user_choice
        file_path="${file_paths[$user_choice - 1]}"
      else
        file_path="${file_paths[0]}"
      fi

      dotted_path=$(make_dotted_path "$file_path" "$class_name")

      django_test_options="${*:2}"
    #
    # module or package
    #
    else
      # multiple threads seem to degrade performance
      path=$(fd --threads 1 --type file --type directory | fzf)

      dotted_path=$(make_dotted_path "$path")

      django_test_options="$*"
    fi
    run_test "$dotted_path" "$django_test_options"
  fi

  [ "$src_dir" == true ] && cd ..
  cleanup
}

trap user_interrupt SIGINT
trap user_interrupt SIGTSTP

main "$@"
