#!/usr/bin/env bash

set -eu

GIT_CI_DIR=git-ci
declare -A OCCASIONAL_FAILURE_ATTEMPTS=([t1410]=50 [t9128]=50 [t9141]=50 [t9167]=100)

run_until_success () {
	runs="$1"; shift
	for (( n=0; n<runs; n++ ))
	do
		"$@" && return 0
	done
	return 1
}

build_test_branch () {
	git clean -dff -e "$GIT_CI_DIR"/ || return 3
	git reset --hard origin/"$1" || return 3

	make -j4 configure || return 1
	./configure || return 1
	make -j4 all || return 1

	for patchfile in "$GIT_CI_DIR"/*.diff "$GIT_CI_DIR"/"$1"/*.diff
	do
		if [[ -r "$patchfile" ]]
		then
			patch -p1 <"$patchfile" || return 2
		fi
	done

	cd t || return 2
	make DEFAULT_TEST_TARGET=prove GIT_PROVE_OPTS='--jobs 4' GIT_SKIP_TESTS="${!OCCASIONAL_FAILURE_ATTEMPTS[*]}" all || return 1

	for test_script in "${!OCCASIONAL_FAILURE_ATTEMPTS[@]}"
	do
		full_script_name=("$test_script"-*.sh)
		run_until_success "${OCCASIONAL_FAILURE_ATTEMPTS["$test_script"]}" ./"${full_script_name[0]}" -i || return 1
	done
	cd -

	git clean -dff -e "$GIT_CI_DIR"/ || return 3
	git reset --hard || return 3
}

update_branch_details () {
	branches=()
	while read -r line
	do
		branches+=("$line")
	done <"$GIT_CI_DIR/branches"

	unset hashes
	declare -Ag hashes
	for branch in "${branches[@]}"
	do
		if [[ -r "$GIT_CI_DIR/$branch/last-success" ]]
		then
			hashes["$branch"]="$(<"$GIT_CI_DIR/$branch/last-success")"
		else
			hashes["$branch"]=
		fi
	done
}

while :
do
	git fetch

	update_branch_details

	built_something=
	for branch in "${branches[@]}"
	do
		new_hash=$(git rev-parse origin/"$branch")
		if [[ "$new_hash" != "${hashes["$branch"]}" ]]
		then
			date
			echo "Building origin/$branch ($new_hash)"
			if ! time build_test_branch "$branch"
			then
				echo "Failed building origin/$branch"
				echo "Failing hash was $new_hash"
				echo "Last success on this branch was ${hashes["$branch"]}"
				exit 1
			fi
			built_something=yes
			mkdir -p "$GIT_CI_DIR/$branch"
			echo "$new_hash" >"$GIT_CI_DIR/$branch/last-success"
			date
			echo "Finished building origin/$branch"
		fi
	done

	if [[ -z $built_something ]]
	then
		# Haven't built anything.  Sleep for 10 minutes to avoid
		# tightlooping.
		echo "Sleeping for 10 minutes"
		sleep 600
		date
	fi
done
