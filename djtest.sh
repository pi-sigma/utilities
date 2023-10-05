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
package.

Provide the -r flag to run the previous test together with any Django options specified
on the last run. In order to run the previous test and override Django options, provide
the -c flag in addition. For example,

    . djtest.sh -r -c --verbosity=2

will run the previous test with --verbosity=2 and create a new database, even if the
last run was made with --keepdb.\n"


handle_options() {
  while (( $# )); do
    case $1 in
      -h | --help)
      help=true
      ;;
      -r | --repeat)
      repeat=true
    case $2 in
      -c | --clear)
        clear_options=true
        ;;
    esac
    esac
    shift
  done
}

##############################################################################
# Get class definition from file
# Arguments:
#   file_path - foo/bar/baz.py
#   method - test_foo_bar
# Outputs:
#   class definition - class FooTest(TestCase)
# Details:
#   Gets start_line for search by reading file in reverse, stopping at method;
#   reads file in reverse from start_line, stopping at first class definition
##############################################################################
get_class_def() {
  local file_path=$1
  local method=$2
  local start_line=$(tac $file_path | rg -n $method | cut -f1 -d:)
  local class_def=$(tac $file_path | sed -n ''$start_line',$p' | rg '(?<=class ).+[A-Za-z]+' --pcre2)
  echo $class_def
}

###################################
# Get name of test class
# Arguments:
#   class_def
# Outputs:
#   name of test class - FooBarTest
###################################
get_class_name() {
  local cls_name=$@
  cls_name=${cls_name%%(*}
  cls_name=${cls_name:6}
  echo "${cls_name}"
}

get_first_arg() {
  echo $1 | cut -d' ' -f1
}

##############################################################################
# Make dotted path
# Arguments:
#   file_path
#   class_name (optional)
#   method (optional)
# Returns:
#   a dotted path (foo.bar.BazTest.test_example)
# Details:
#   Strips extension or traling slash from file_path and replaces '/' with '.'.
#   Attaches class_name and method, if applicable.
##############################################################################
make_dotted_path() {
  local arg=$1
  local path

  if [[ $arg == *.py ]]; then
    path=${arg::-3}
  else
    path=${arg::-1}
  fi

  local dotted_path=${path//\//.}
  [ $2 ] && dotted_path+=".$2"
  [ $3 ] && dotted_path+=".$3"
  echo $dotted_path
}

################################
# Run test
# Globals:
#   previous_django_test
#   django_test_options
# Arguments:
#   dotted_path
# Outputs:
#   Writes dotted_path to stdout
################################
run_test() {
  previous_django_test="python manage.py test $1"
  [ $1 != "" ] && eval "${previous_django_test}" "${django_test_options}"  && echo ">>> $1 <<<"
}

#####################################################
# Display file paths
# Globals:
#   file_paths
#   ITER
# Details:
#   Displays file paths where a method/class is found
#####################################################
show_options() {
  echo $'The name of the test method/class was found in several places:\n'

  # make file paths unique
  file_paths=($(printf "%q\n" "${file_paths[@]}" | uniq))

  ITER=1
  for elem in ${file_paths[@]}; do  
    echo "${ITER}) ${elem}"
    ((ITER++))
  done
}

cleanup() {
  unset class_name clear_options dotted_path file_path file_paths help help_msg ITER num_paths
  unset repeat src_dir target user_choice
}


main() {
  [ -d src ] && cd src/ && src_dir=true
  [ -d app ] && cd app/ && src_dir=true

  handle_options "$@"

  if [ "$help" = true ]; then
    printf "${help_msg}"
  elif [ "$repeat" = true ]; then
    echo "Running previous test..."

    if [ "$clear_options" = true ]; then
      django_test_options=${@:3}
    fi

    eval $previous_django_test $django_test_options
  else
    target=(${@:1})
    # method
    if [[ $target =~ test[a-z_0-9]+$ ]]; then
      method=$(get_first_arg $@)

      # Read string with path(s) of module(s) containing method into array, splitting on '\n'
      IFS=$'\n' file_paths=($(rg "$method" | rg -o '^[^:]+'))

      # check number of file paths found
      # for some reason, this does not work inside a function;
      # read -p is executed out of order
      num_paths="${#file_paths[@]}"
      if [[ $num_paths -gt 1 ]]; then
        show_options
        read -p $'\nSelect a file path: ' user_choice
        file_path="${file_paths[$user_choice - 1]}"
      else
        file_path="${file_paths[0]}"
      fi

      class_name=$(get_class_name $(get_class_def $file_path $method))

      dotted_path=$(make_dotted_path $file_path $class_name $method)

      django_test_options=${@:2}
    # class
    elif [[ $target =~ [\'Test\']?[A-Za-z][Test][s]?$ ]] || [[ $target =~ Test[A-Za-zT]+$ ]]; then
      class_name=$(get_first_arg $@)

      # Read string with path(s) of module(s) containing method into array, splitting on '\n'
      IFS=$'\n' file_paths=($(rg "$class_name" | rg -o '^[^:]+'))

      # check number of file paths found
      # for some reason, thi does not work inside a function;
      # read -p is executed out of order
      num_paths="${#file_paths[@]}"
      if [[ $num_paths -gt 1 ]]; then
        show_options
        read -p $'\nSelect a file path: ' user_choice
        file_path="${file_paths[$user_choice - 1]}"
      else
        file_path="${file_paths[0]}"
      fi

      dotted_path=$(make_dotted_path $file_path $class_name)

      django_test_options=${@:2}
    # module or package
    else
      path=$(fd --threads 1 --type file --type directory | fzf)

      dotted_path=$(make_dotted_path $path)

      django_test_options=$@
    fi
    run_test $dotted_path $django_test_options
  fi

  [ "$src_dir" == true ] && cd ..
  cleanup
}

main "$@"
