#!/usr/bin/perl

# Lubomir Rintel <lkundrak@v3.sk>, 2014

use strict;
use warnings;

use URI;
use URI::Escape;
use JSON;
use LWP::UserAgent;
use Database::DumpTruck;

my $this_year = 1900 + [localtime]->[5];
my $root = new URI 'http://www.digitalnemesto.sk/';
my $ua = new LWP::UserAgent;
my $dt = new Database::DumpTruck ({ dbname => 'data.sqlite' });

# We assign numerical ids to these so that we sort them into a fixed order
# for the purposes of keeping track of where we've left
my @tabs = (
	{ id => 0, name => 'invoicesd' },
	{ id => 1, name => 'invoiceso' },
	{ id => 2, name => 'orders' },
	{ id => 3, name => 'contracts' },
);

# Sorting helper, for record-tracking purposes
sub idsort { sort { $a->{id} <=> $b->{id} } @_; }

my $rsp;
$SIG{__DIE__} = sub {
	die @_ if $^S;
	use Data::Dumper;
	warn Dumper $rsp;
};


# JSON RPC
sub call
{
	my $call = shift;

	# query_form-formatted params are passed in path component
	my $params = new URI;
	$params->query_form (procedure => $call, @_);
	$params->opaque =~ /.(.*)/; # strip leading ? from query params
	my $uri = new URI ("/getjsondata/$1")->abs ($root);
	my $time = time;

	# Backend is known to return incomplete responses from time to time
	my ($response, $response2);
	do {
		warn "Retry: Inconsistent response for GET $uri" if $response;
if ($response) {
use Data::Dumper;
warn Dumper $rsp;
sleep 1;
}

		# First try
		$uri->query_form (['dojo.preventCache' => $time++, @_]);
		$response = $ua->get ($uri);

		# Verify
		$uri->query_form (['dojo.preventCache' => $time++, @_]);
		$response2 = $ua->get ($uri);
$rsp = [ $response, $response2 ];
	} while (length $response->decoded_content != length $response2->decoded_content or length $response->decoded_content < 14);
	die $response->status_line unless $response->is_success;

	my $content = $response->decoded_content;

	# This resource used to return HTML with Content-Type: application/json:
	# http://www.digitalnemesto.sk/getjsondata/procedure=getinvoicesd&idCity=508250000&year=2013?dojo.preventCache=1406818754
	unless ($content =~ /^[\[{]/) {
		warn "Skipping: Not a JSON response for GET $uri";
		return ();
	}

	$content =~ s/\t/ /g; # https://rt.cpan.org/Ticket/Display.html?id=97558
	return @{new JSON::XS->utf8->relaxed->decode ($content)->{items}};
}

# Format into database
sub fmt
{
	# Merge
	my %data = map { %$_ } @_;

	# Flatten
	foreach my $key (keys %data) {
		$data{$key} = $data{$key}{_value} if ref $data{$key} eq 'HASH';
		$data{$key} = join "\n", @{$data{$key}} if ref $data{$key} eq 'ARRAY';
		delete $data{$key} if ref $data{$key};
	}

	return \%data;
}

# Walk a single tab for given city/year. Resuming where we left.
sub dotab
{
	my $tab = shift;
	my $partner = shift;
	my $year = shift;

	my $last_var = "$year.$partner->{id}.$tab->{id}.last";
	my $last_id = eval { $dt->get_var ($last_var) } || 0;

	foreach my $item (idsort(call ("get$tab->{name}", idCity => $partner->{id}, year => $year))) {

		# Already seen this
		next unless $item->{id} > $last_id;

		my ($details) = call ("get$tab->{name}detail", idMesto => $partner->{id}, id => $item->{id});
		my $entry = fmt ($item, $details, { mesto => $partner->{name},
			year => $year, @_ });

		$dt->insert($entry, $tab->{name});
		$dt->save_var ($last_var, $item->{id});
	}
}

# Start the ball rolling
foreach my $year (2013..$this_year) {
	foreach my $tab (idsort(@tabs)) {
		foreach my $partner (idsort(call ('getpartners'))) {
			dotab ($tab, $partner, $year);
		}
	}
}
