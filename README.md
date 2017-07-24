This is a very basic contiuous integration script for Git.  Run it from the
root of a Git repository, and it'll spin through the `master`, `maint`, `pu`
and `next` branches, build and test them, and bail out if it hits any errors.

I've created a new script from scratch rather than using anything extant as I
want to run this on Cygwin, and the only ready-made CI server I've been able to
find for Cygwin is [BuildBot](https://buildbot.net), which appears to be
painfully slow when running in Cygwin.
