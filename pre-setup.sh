#!/bin/bash

set -e

# consider using a yum repo
SRC="https://buildhub.dev.cpanel.net/RPM/11.126/centos/8/x86_64/"
SRC="src" # for now use local src (no packages built on buildhub)

PERL=/usr/local/cpanel/3rdparty/bin/perl540

echo "Removing perl older versions of Perl"
for V in "532" "535" "536" "540"; do
    [ -e /usr/local/cpanel/3rdparty/perl/$V/bin/perl ] && rpm -e --nodeps cpanel-perl-$V ||:
done

rpm -Uv --force $SRC/cpanel-perl-540-5.40.0-1.cp126~el8.x86_64.rpm ||:

echo "Setup 5.40 from 5.39"
[ -e /usr/local/cpanel/3rdparty/perl/540 ] || ln -sf /usr/local/cpanel/3rdparty/perl/539 /usr/local/cpanel/3rdparty/perl/540
ln -sf /usr/local/cpanel/3rdparty/bin/perl539 /usr/local/cpanel/3rdparty/bin/perl540

echo "Setting perl & prove for 540"

ln -sf /usr/local/cpanel/3rdparty/perl/540/bin/prove /usr/local/cpanel/3rdparty/bin/prove

# # we now whave some custom RPMs available install and use them if possible
# rpm -Uv --force \
#     $SRC/cpanel-perl-532-DBI-1.643-1.cp1194.x86_64.rpm \
#     $SRC/cpanel-perl-532-DBD-SQLite-1.66-1.cp1194.x86_64.rpm \
#     $SRC/cpanel-perl-532-DBD-Pg-3.14.2-1.cp1194.x86_64.rpm \
#     $SRC/cpanel-perl-532-DBD-mysql-4.050-1.cp1194.x86_64.rpm

# echo "Installing Test2 & modules used for testing"

# RPMS="cpanel-perl-532-App-cpanminus-1.7044-1.cp1194.noarch.rpm \
#     cpanel-perl-532-AppConfig-1.71-1.cp1194.noarch.rpm \
#     cpanel-perl-532-B-Flags-0.17-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Capture-Tiny-0.48-1.cp1194.noarch.rpm \
#     cpanel-perl-532-CBOR-Free-0.31-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Class-Accessor-0.51-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Class-Load-0.25-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Class-Load-XS-0.10-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Class-Method-Modifiers-2.13-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Class-XSAccessor-1.19-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-common-sense-3.75-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Data-Dump-1.23-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Data-OptList-0.110-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Devel-GlobalDestruction-0.14-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Devel-OverloadInfo-0.005-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Devel-StackTrace-2.04-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Digest-HMAC-1.03-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Dist-CheckConflicts-0.11-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Encode-Locale-1.05-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Eval-Closure-0.14-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Exporter-Tiny-1.002002-1.cp1194.noarch.rpm \
#     cpanel-perl-532-File-Listing-6.11-1.cp1194.noarch.rpm \
#     cpanel-perl-532-File-Slurp-9999.32-1.cp1194.noarch.rpm \
#     cpanel-perl-532-HTML-Parser-3.75-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-HTML-Tagset-3.20-1.cp1194.noarch.rpm \
#     cpanel-perl-532-HTTP-Cookies-6.08-1.cp1194.noarch.rpm \
#     cpanel-perl-532-HTTP-Daemon-6.12-1.cp1194.noarch.rpm \
#     cpanel-perl-532-HTTP-Date-6.05-1.cp1194.noarch.rpm \
#     cpanel-perl-532-HTTP-Message-6.26-1.cp1194.noarch.rpm \
#     cpanel-perl-532-HTTP-Negotiate-6.01-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Importer-0.026-1.cp1194.noarch.rpm \
#     cpanel-perl-532-IO-HTML-1.004-1.cp1194.noarch.rpm \
#     cpanel-perl-532-IO-Socket-INET6-2.72-1.cp1194.noarch.rpm \
#     cpanel-perl-532-IO-Socket-SSL-2.068-1.cp1194.noarch.rpm \
#     cpanel-perl-532-IO-Stringy-2.113-1.cp1194.noarch.rpm \
#     cpanel-perl-532-JSON-XS-4.03-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-libwww-perl-6.49-1.cp1194.noarch.rpm \
#     cpanel-perl-532-List-MoreUtils-0.430-1.cp1194.noarch.rpm \
#     cpanel-perl-532-List-MoreUtils-XS-0.430-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-LWP-MediaTypes-6.04-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Module-Build-0.4231-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Module-Implementation-0.09-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Module-Pluggable-5.2-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Module-Runtime-0.016-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Module-Runtime-Conflicts-0.003-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Moo-2.004000-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Moose-2.2013-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-MooseX-NonMoose-0.26-1.cp1194.noarch.rpm \
#     cpanel-perl-532-MRO-Compat-0.13-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Net-DNS-1.27-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Net-HTTP-6.19-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Net-LibIDN-0.12-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Net-SSLeay-1.88-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Package-DeprecationManager-0.17-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Package-Stash-0.38-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Package-Stash-XS-0.29-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Params-Util-1.101-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Ref-Util-XS-0.117-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Role-Tiny-2.001004-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Sereal-4.018-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Sereal-Decoder-4.018-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Sereal-Encoder-4.018-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Scope-Guard-0.21-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Socket6-0.29-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Sub-Exporter-0.987-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Sub-Exporter-Progressive-0.001013-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Sub-Identify-0.14-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Sub-Info-0.002-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Sub-Install-0.928-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Sub-Name-0.26-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Sub-Quote-2.006006-1.cp1194.noarch.rpm \
#     cpanel-perl-532-TAP-Formatter-JUnit-0.11-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Template-Toolkit-3.009-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-Term-Table-0.015-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Test-Deep-1.130-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Test-Fatal-0.016-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Test-Simple-1.302183-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Test-Trap-v0.3.4-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Test2-Plugin-NoWarnings-0.09-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Test2-Suite-0.000138-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Test2-Tools-Explain-0.02-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Text-Control-0.5-1.cp1194.noarch.rpm \
#     cpanel-perl-532-TimeDate-2.33-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Try-Tiny-0.30-1.cp1194.noarch.rpm \
#     cpanel-perl-532-Types-Serialiser-1.0-1.cp1194.noarch.rpm \
#     cpanel-perl-532-URI-5.05-1.cp1194.noarch.rpm \
#     cpanel-perl-532-WWW-RobotRules-6.02-1.cp1194.noarch.rpm \
#     cpanel-perl-532-XML-Generator-1.04-1.cp1194.noarch.rpm \
#     cpanel-perl-532-XML-Parser-2.46-1.cp1194.x86_64.rpm \
#     cpanel-perl-532-X-Tiny-0.21-1.cp1194.noarch.rpm \
#     cpanel-perl-532-XString-0.005-1.cp1194.x86_64.rpm"

# TO_INSTALL=""
# for rpm in $RPMS; do
#     echo -n "Checking $rpm: ";
#     curl --fail -s -I $SRC/$rpm >/dev/null;
#     echo -e " \e[32mOK\e[0m"
#     TO_INSTALL="${TO_INSTALL} $SRC/$rpm"
# done

# rpm -Uv --force $TO_INSTALL

cd src
$PERL install-perl-modules.pl
$PERL -MTAP::Formatter::JUnit -E "say q[perl installed with TAP::Formatter::JUnit];"

echo "Using prove: "
ls -l /usr/local/cpanel/3rdparty/bin/prove
