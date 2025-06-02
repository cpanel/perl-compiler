#!perl

# Test interaction of threads and directory handles.

BEGIN {
     chdir 't' if -d 't';
     require './test.pl';
     set_up_inc('../lib');
     $| = 1;

     require Config;
     skip_all_without_config('useithreads');
     skip_all_if_miniperl("no dynamic loading on miniperl, no threads");
     skip_all("runs out of memory on some EBCDIC") if $ENV{PERL_SKIP_BIG_MEM_TESTS};     
}

use strict;
use warnings;
use threads;
use threads::shared;
use File::Path;
use File::Spec::Functions qw 'updir catdir';
use Cwd 'getcwd';

plan(6);

# Basic sanity check: make sure this does not crash
fresh_perl_is <<'# this is no comment', 'ok', {}, 'crash when duping dirh';
   use threads;
   opendir dir, 'op';
   async{}->join for 1..2;
   print "ok";
# this is no comment
