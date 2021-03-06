use strict;
use warnings;
use 5.010;

use Path::Tiny qw(path);
use Getopt::Long qw(GetOptions);
use Pod::Usage qw(pod2usage);

GetOptions( 'source:s' => \my $source );

=head1 USAGE

  fetch.pl [--source german-perl-workshop-2014] $URLs

=cut

use lib path($0)->absolute->parent->parent->child('lib')->stringify;
use PerlTV::Fetch;

pod2usage() if not @ARGV;
my $fetch = PerlTV::Fetch->new(
    source => $source,
);
foreach my $url (@ARGV) {
	eval {
		$fetch->process($url);
	};
	if ($@) {
		print $@;
	}
}

