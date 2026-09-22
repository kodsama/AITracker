import 'dart:io';

/// Shows [path] in Finder.
///
/// A variable rather than a call so a test can watch what would have been
/// opened instead of opening it.
void Function(String path) revealInFinder = (path) =>
    Process.runSync('/usr/bin/open', ['-R', path]);
