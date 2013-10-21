package PerlTV;
use Dancer2;

our $VERSION = '0.01';
use Cwd qw(abs_path);
use Path::Tiny ();
use JSON::Tiny ();
use Data::Dumper qw(Dumper);
use List::Util qw(min);

use PerlTV::Tools qw(read_file);

hook before => sub {
	my $appdir = abs_path config->{appdir};
	my $json = JSON::Tiny->new;
	set people => $json->decode( Path::Tiny::path("$appdir/people.json")->slurp_utf8 );
	set sources => $json->decode( Path::Tiny::path("$appdir/sources.json")->slurp_utf8 );
	set tags => $json->decode( Path::Tiny::path("$appdir/tags.json")->slurp_utf8 );
	set modules => $json->decode( Path::Tiny::path("$appdir/modules.json")->slurp_utf8 );
	my $featured = $json->decode( Path::Tiny::path("$appdir/featured.json")->slurp_utf8 );
	set featured => [ sort {$b->{date} cmp $a->{date} }  @$featured ];
	my $data;
	eval {
		$data = $json->decode( Path::Tiny::path("$appdir/videos.json")->slurp_utf8 );
	};
	if ($@) {
		set error => 'Could not load videos.json, have you generated it?';
		warn $@;
	} elsif (defined $data) {
		set data => $data;
	} else {
		set error => $json->error;
		warn $json->error;
	}
};

hook before_template => sub {
	my $t = shift;
	if (not $t->{title} or request->path eq '/') {
		$t->{title} = 'Perl TV';
	}

	my $THUMBNAILS = 4; # shown at the bottom of the front page
	$t->{social} = 1;
	$t->{request} = request;
	my $featured = setting('featured');
	my $end = min($THUMBNAILS, @$featured-1);
	$t->{featured} = [ @{$featured}[1 .. $end] ];

	if ($t->{video} and $t->{video}{start}) {
		my ($min, $sec) = split /:/, $t->{video}{start};
		$t->{video}{start} = $min * 60 + $sec;
	}

	if ($t->{video} and $t->{video}{source}) {
		my $sources = setting('sources');
		$t->{video}{source_name} = $sources->{ $t->{video}{source} }{name};
	}

	if ($t->{video} and $t->{video}{speaker}) {
		my $people = setting('people');
		$t->{video}{speaker_name} = $people->{ $t->{video}{speaker} }{name};
		$t->{video}{speaker_home} = $people->{ $t->{video}{speaker} }{home};
		$t->{video}{speaker_nickname} = $people->{ $t->{video}{speaker} }{nickname};
	}
	if ($t->{video} and not $t->{video}{thumbnail}) {
		$t->{video}{thumbnail} = "http://img.youtube.com/vi/$t->{video}{id}/default.jpg";
	#die $t->{video}{thumbnail};
	}

	return;
};

get '/legal' => sub {
	template 'legal';
};

#	my $error = setting('error');
#	if ($error) {
#		warn $error;
#		return template 'error';
#	}

get '/all' => sub {
	my $data = setting('data');
	template 'list', { videos => $data->{videos} };
};

get '/people/?' => sub {
	my $people = setting('people');
	template 'list_people', { people => $people };
};

get '/people/:person' => sub {
	my $people = setting('people');
	my $person = params->{person};
	pass if not $people->{$person};

	my $data = setting('data');
	my @entries = grep { $_->{speaker} eq $person} @{ $data->{videos} };
	template 'list', { videos => \@entries, %{ $people->{$person} } };
};

get '/tag/?' => sub {
	my $tags = setting('tags');
	template 'list_tags', { tags => $tags };
};

get '/tag/:tag' => sub {
	my $tags = setting('tags');
	my $tag = params->{tag};
	pass if not $tags->{$tag};
	template 'list', { videos => $tags->{$tag}, tag => $tag };
};

get '/module/?' => sub {
	my $modules = setting('modules');
	template 'list_modules', { modules => $modules };
};

get '/module/:name' => sub {
	my $modules = setting('modules');
	my $name = params->{name};
	pass if not $modules->{$name};
	template 'list', { videos => $modules->{$name}, module => $name };
};

get '/source/?' => sub {
	my $sources = setting('sources');
	template 'list_sources', { sources => $sources };
};

get '/source/:name' => sub {
	my $sources = setting('sources');
	my $name = params->{name};
	pass if not $sources->{$name};
	my $data = setting('data');
	my @entries = grep { $_->{source} eq $name} @{ $data->{videos} };
	template 'list', { videos => \@entries, %{ $sources->{$name} } };
};


get '/' => sub {
	# show the currently featured item
	my $featured = setting('featured');
	my @modules = sort {lc $a cmp lc $b} keys %{ setting('modules') };
	my @tags    = sort {lc $a cmp lc $b} keys %{ setting('tags') };
	_show('index', $featured->[0]{path}, {
		#show_tags    => 1,
		#show_modules => 1,
		#tags         => \@tags,
		#modules      => \@modules,
	});
};

get '/v/:path' => sub {
	my $path = params->{path};
	if ($path =~ /^[A-Za-z_-]+$/) {
		return _show('page', $path, {show_tags => 1, show_modules => 1});
	} else {
		warn "Could not find '$path'";
		return template 'error';
	}
};

get '/daily.atom' => sub {
	my $featured = setting('featured');
	my $appdir = abs_path config->{appdir};

	my $URL = request->base;
	$URL =~ s{/$}{};
	my $title = 'PerlTV daily';
	my $ts = $featured->[0]{date};

	my $xml = '';
	$xml .= qq{<?xml version="1.0" encoding="utf-8"?>\n};
	$xml .= qq{<feed xmlns="http://www.w3.org/2005/Atom">\n};
	$xml .= qq{<link href="$URL/daily.atom" rel="self" />\n};
	$xml .= qq{<title>$title</title>\n};
	$xml .= qq{<id>$URL/</id>\n};
	$xml .= qq{<updated>${ts}Z</updated>\n};
	foreach my $entry (@$featured) {

		my $data = read_file( "$appdir/data/videos/$entry->{path}" );

		$xml .= qq{<entry>\n};

		$xml .= qq{  <title>$data->{title}</title>\n};
		$xml .= qq{  <summary type="html"><![CDATA[$data->{description}]]></summary>\n};
		$xml .= qq{  <updated>$entry->{date}Z</updated>\n};
		my $url = "$URL/v/$entry->{path}";
		$xml .= qq{  <link rel="alternate" type="text/html" href="$url" />};
		$xml .= qq{  <id>$entry->{path}</id>\n};
		$xml .= qq{  <content type="html"><![CDATA[$data->{description}]]></content>\n};
		$xml .= qq{</entry>\n};
	}
	$xml .= qq{</feed>\n};

	content_type 'application/atom+xml';
	return $xml;
};

get '/sitemap.xml' => sub {
	my $data = setting('data');
	my $url = request->base;
	$url =~ s{/$}{};
	content_type 'application/xml';

	my $xml = qq{<?xml version="1.0" encoding="UTF-8"?>\n};
	$xml .= qq{<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};
	$xml .= qq{  <url>\n};
	$xml .= qq{    <loc>$url/</loc>\n};
	$xml .= qq{  </url>\n};
	foreach my $p (@{ $data->{videos} }) {
		$xml .= qq{  <url>\n};
		$xml .= qq{    <loc>$url/v/$p->{path}</loc>\n};
		#$xml .= qq{    <changefreq>monthly</changefreq>\n};
		#$xml .= qq{    <priority>0.8</priority>\n};
		$xml .= qq{  </url>\n};
	}
	$xml .= qq{</urlset>\n};
	return $xml;
};

sub _show {
	my ($template, $path, $params) = @_;

	$params ||= {};

	my $appdir = abs_path config->{appdir};
	my $data;
	eval {
		$data = read_file( "$appdir/data/videos/$path" );
	};
	if ($@) {
		#warn $@;
		return template 'error';
	}

	$data->{path} = $path;
	template $template, { 
		video   => $data,
		tags    => $data->{tags},
		modules => $data->{modules},
		title   => $data->{title},
		%$params,
	};
};


true;

