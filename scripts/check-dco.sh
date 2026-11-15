#!/bin/sh
# Copyright 2026 The oneberth Authors
# SPDX-License-Identifier: Apache-2.0
#
# Every commit of a branch is signed off by the person who put it there --
# its author, or whoever committed someone else's work -- as CONTRIBUTING.md
# requires. Takes a commit range, and defaults to the commits this branch adds
# to main -- never the whole history, part of which predates the rule.
#
# A commit also names no AI tool: "Claude" or "claude" appears nowhere in its
# message, its author or its committer.
#
#     scripts/check-dco.sh                     the commits of this branch
#     scripts/check-dco.sh <base>..<head>      the commits of a pull request
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

range=${1:-}
asked_for=yes
if [ -z "$range" ]; then
    asked_for=no
    base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)
    range="$base..HEAD"
fi

# Merge commits carry no contribution of their own; GitHub's own DCO check
# skips them too.
commits=$(git rev-list --no-merges "$range")
in_range=$(git rev-list --count "$range")

if [ "$in_range" -eq 0 ]; then
    if [ "$asked_for" = no ]; then
        # On main, or on a branch that has added nothing yet. There is
        # genuinely nothing to certify, and nothing wrong with that.
        printf 'This branch adds no commit to main; nothing to certify.\n'
        exit 0
    fi
    printf '%s contains no commits. There is nothing to certify here, which is\n' "$range"
    printf 'not the same as a branch whose commits are signed off: check the range.\n'
    exit 1
fi

checked=0
failed=0
for commit in $commits; do
    checked=$((checked + 1))
    # Each git call is a command of its own: in a pipeline its failure would
    # be swallowed and read as "not signed off", which is the right answer for
    # the wrong reason.
    author=$(git show -s --format='%an <%ae>' "$commit")
    committer=$(git show -s --format='%cn <%ce>' "$commit")
    subject=$(git show -s --format='%h %s' "$commit")
    trailers=$(git show -s --format='%(trailers:key=Signed-off-by,valueonly,unfold)' "$commit")
    signed=$(printf '%s\n' "$trailers" | tr '[:upper:]' '[:lower:]')
    message=$(git show -s --format='%B' "$commit")

    # No AI tool in the commit: GitHub lists an author or committer such as
    # "Claude <noreply@anthropic.com>" as a contributor, and the AI disclosure
    # belongs in the pull request's description.
    named=$(printf 'Author: %s\nCommitter: %s\n%s\n' "$author" "$committer" "$message" |
        grep -n '[Cc]laude' || true)
    bad=no
    if [ -n "$named" ]; then
        bad=yes
        printf 'FAIL %s\n' "$subject"
        printf '     names "Claude"; remove it from the message, author and committer:\n'
        printf '%s\n' "$named" | sed 's/^/       /'
    fi

    # The DCO is certified by whoever puts the commit here: its author, or the
    # person who took someone else's work over and committed it. That second
    # case is how a Dependabot pull request is merged (CONTRIBUTING.md).
    matched=no
    for who in "$author" "$committer"; do
        wanted=$(printf '%s' "$who" | tr '[:upper:]' '[:lower:]')
        if printf '%s\n' "$signed" | grep -qxF "$wanted"; then
            matched=yes
            break
        fi
    done
    if [ "$matched" = no ]; then
        bad=yes
        printf 'FAIL %s\n' "$subject"
        printf '     no trailer "Signed-off-by: %s"' "$author"
        if [ "$committer" != "$author" ]; then
            printf ' or "Signed-off-by: %s"' "$committer"
        fi
        printf '; commit with git commit -s\n'
    fi
    if [ "$bad" = yes ]; then
        failed=$((failed + 1))
    fi
done

if [ "$failed" -ne 0 ]; then
    printf '\n%d of %d commit(s) in %s are not signed off, or name "Claude".\n' \
        "$failed" "$checked" "$range"
    exit 1
fi
if [ "$checked" -eq 0 ]; then
    printf '%s holds %d commit(s), all of them merges, and a merge certifies\n' "$range" "$in_range"
    printf 'nothing of its own. Nothing to check.\n'
    exit 0
fi
printf 'All %d commit(s) in %s are signed off, and none names "Claude".\n' "$checked" "$range"
