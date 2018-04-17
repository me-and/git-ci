#!/usr/bin/env bash

set -eu

THREADS=${THREADS:-$(($(nproc 2>/dev/null) + 1))}

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
	git submodule update --init || return 3

	make -j "$THREADS" configure || return 1
	./configure || return 1
	make -j "$THREADS" all || return 1

	for patchfile in "$GIT_CI_DIR"/*.diff "$GIT_CI_DIR"/"$1"/*.diff
	do
		if [[ -r "$patchfile" ]]
		then
			patch -p1 <"$patchfile" || return 2
		fi
	done

	(
		cd t || return 2
		make DEFAULT_TEST_TARGET=prove GIT_TEST_OPTS='-l' GIT_PROVE_OPTS="--jobs $THREADS" GIT_SKIP_TESTS="${!OCCASIONAL_FAILURE_ATTEMPTS[*]}" all || return 1

		for test_script in "${!OCCASIONAL_FAILURE_ATTEMPTS[@]}"
		do
			full_script_name=("$test_script"-*.sh)
			run_until_success "${OCCASIONAL_FAILURE_ATTEMPTS["$test_script"]}" ./"${full_script_name[0]}" -i || return 1
		done
	) || return $?

	git clean -dff -e "$GIT_CI_DIR"/ || return 3
	git reset --hard || return 3
}

rc=0

git fetch

built_something=
for branch in $(git config --get-all git-ci.branch)
do
	new_hash=$(git rev-parse origin/"$branch")
	if [[ "$new_hash" != "$(git config "git-ci.${branch}.last-success")" ]]
	then
		date
		echo "Building origin/$branch ($new_hash)"
		if time build_test_branch "$branch"
		then
			git config "git-ci.${branch}.last-success" "$new_hash"
		else
			echo "Failed building origin/$branch"
			echo "Failing hash was $new_hash"
			echo "Last success on this branch was $(git config "git-ci.${branch}.last-success")"
			rc=1
		fi
		built_something=yes
		date
		echo "Finished building origin/$branch"
	else
		echo "Skipping origin/$branch ($new_hash)"
		echo "Already verified $(git config "git-ci.${branch}.last-success")"
	fi
done

exit "$rc"
