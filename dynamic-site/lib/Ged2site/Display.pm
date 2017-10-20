package Ged2site::Display;

# Display a page. Certain variables are available to all templates, such as
# the stuff in the configuration file

use strict;
use warnings;

use Ged2site::Config;
use Ged2site::Allow;
use CGI::Info;
use Error;
use Fatal qw(:void open);

use Template::Filters;
use Template::Plugin::EnvHash;
use HTML::SocialMedia;

our $sm;
our $smcache;

sub new {
	my $proto = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $class = ref($proto) || $proto;

	my $info = $args{info} || CGI::Info->new();
	my $config = $args{config} || Ged2site::Config->new({ logger => $args{logger}, info => $info, lingua => $args{lingua} });

	unless($info->is_search_engine() || !defined($ENV{'REMOTE_ADDR'})) {
		my %allowargs = (
			info => $info,
			config => $config,
			lingua => $args{lingua},
			logger => $args{logger},
			cachedir => $args{cachedir},
			cache => $args{cache}
		);
		unless(Ged2site::Allow::allow(%allowargs)) {
			throw Error::Simple("Not allowing connexion from $ENV{'REMOTE_ADDR'}", 1);
		}
	}

	Template::Filters->use_html_entities();

	my $self = {
		_config => $config,
		_info => $info,
		_lingua => $args{lingua},
		_logger => $args{logger},
		_cachedir => $args{cachedir},
		# _page => $info->param('page'),
	};

	if(my $key = $info->param('key')) {
		$self->{'_key'} = $key;
	}

	if(my $twitter = $config->{'twitter'}) {
		$smcache ||= ::create_memory_cache(config => $config, logger => $args{'logger'}, namespace => 'HTML::SocialMedia');
		$sm ||= HTML::SocialMedia->new({ twitter => $twitter, cache => $smcache, lingua => $args{lingua}, logger => $args{logger} });
		$self->{'_social_media'}->{'twitter_tweet_button'} = $sm->as_string(twitter_tweet_button => 1);
	} elsif(!defined($sm)) {
		$smcache = ::create_memory_cache(config => $config, logger => $args{'logger'}, namespace => 'HTML::SocialMedia');
		$sm = HTML::SocialMedia->new({ cache => $smcache, lingua => $args{lingua}, logger => $args{logger} });
	}
	$self->{'_social_media'}->{'facebook_share_button'} = $sm->as_string(facebook_share_button => 1);
	$self->{'_social_media'}->{'google_plusone'} = $sm->as_string(google_plusone => 1);

	return bless $self, $class;
}

sub get_template_path {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	if($self->{_filename}) {
		return $self->{_filename};
	}

	my $dir = $self->{_config}->{rootdir} || $self->{_info}->rootdir();
	if($self->{_logger}) {
		$self->{_logger}->debug("Rootdir: $dir");
	}
	$dir .= '/templates';

	# Look in .../robot or .../mobile first, if appropriate
	my $prefix = '';

	# Look in .../en/gb/web, then .../en/web then /web
	if($self->{_lingua}) {
		my $lingua = $self->{_lingua};

		$self->_debug({ message => 'Requested language: ' . $lingua->requested_language() });

		my $candidate;
		if($lingua->sublanguage_code_alpha2()) {
			$candidate = "$dir/" . $lingua->code_alpha2() . '/' . $lingua->sublanguage_code_alpha2();
			$self->_debug({ message => "check for directory $candidate" });
			if(!-d $candidate) {
				$candidate = undef;
			}
		}
		if((!defined($candidate)) && defined($lingua->code_alpha2())) {
			$candidate = "$dir/" . $lingua->code_alpha2();
			$self->_debug({ message => "check for directory $candidate" });
			if(!-d $candidate) {
				$candidate = undef;
			}
		}
		if($candidate) {
			$prefix = $self->_append_browser_type({ directory => $candidate });
		}
	}

	$prefix .= $self->_append_browser_type({ directory => "$dir/default" });
	$prefix .= $self->_append_browser_type({ directory => $dir });

	# Fall back to .../web, or if that fails, assume no web, robot or
	# mobile variant
	$prefix .= "$dir/web:$dir/default/web:$dir/default:$dir";

	$self->_debug({ message => "prefix: $prefix" });

	my $modulepath = $args{'modulepath'} || ref($self);
	$modulepath =~ s/::/\//g;

	my $filename = $self->_pfopen($prefix, $modulepath, 'tmpl:tt:html:htm:txt');
	if((!defined($filename)) || (!-f $filename) || (!-r $filename)) {
		throw Error::Simple("Can't find suitable $modulepath html or tmpl file in $prefix in $dir or a subdir");
	}
	$self->_debug({ message => "using $filename" });
	$self->{_filename} = $filename;
	return $filename;
}

sub set_cookie {
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	foreach my $key(keys(%params)) {
		$self->{_cookies}->{$key} = $params{$key};
	}
}

sub http {
	my ($self, $params) = @_;

	# TODO: Only session cookies as the moment
	my $cookies = $self->{_cookies};
	if(defined($cookies)) {
		foreach my $cookie (keys(%{$cookies})) {
			if(exists($cookies->{$cookie})) {
				print "Set-Cookie:$cookie=$cookies->{$cookie}; path=/; HttpOnly\n";
			} else {
				print "Set-Cookie:$cookie=0:0; path=/; HttpOnly\n";
			}
		}
	}

	my $language;
	if($self->{_lingua}) {
		$language = $self->{_lingua}->language();
	} else {
		$language = 'English';
	}

	my $rc;

	my $filename = $self->get_template_path();
	if($filename =~ /\.txt$/) {
		$rc = "Content-type: text/plain\n";
	} elsif($language eq 'Japanese') {
		binmode(STDOUT, ':utf8');

		$rc = "Content-type: text/html; charset=UTF-8\n";
	} elsif($language eq 'Polish') {
		binmode(STDOUT, ':utf8');

		# print "Content-type: text/html; charset=ISO-8859-2\n";
		$rc = "Content-type: text/html; charset=UTF-8\n";
	} else {
		$rc = "Content-type: text/html; charset=ISO-8859-1\n";
	}

	# https://www.owasp.org/index.php/Clickjacking_Defense_Cheat_Sheet
	# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Content-Type-Options
	return $rc . "X-Frame-Options: SAMEORIGIN\nX-Content-Type-Options: nosniff\n\n";
}

sub html {
	my ($self, $params) = @_;

	my $filename = $self->get_template_path();
	my $rc;
	if($filename =~ /.+\.t(mpl|t)$/) {
		require Template;
		Template->import();

		my $template = Template->new({
			INTERPOLATE => 1,
			POST_CHOMP => 1,
			ABSOLUTE => 1,
		});

		my $info = $self->{_info};

		# The values in config are defaults which can be overriden by
		# the values in info, then the values in params
		my $vals;
		if(defined($self->{_config})) {
			if($info->params()) {
				$vals = { %{$self->{_config}}, %{$info->params()} };
			} else {
				$vals = $self->{_config};
			}
			if(defined($params)) {
				$vals = { %{$vals}, %{$params} };
			}
		} elsif(defined($params)) {
			$vals = { %{$info->params()}, %{$params} };
		} else {
			$vals = $info->params();
		}
		$vals->{script_name} = $info->script_name();

		$vals->{cart} = $info->get_cookie(cookie_name => 'cart');
		$vals->{lingua} = $self->{_lingua};
		$vals->{social_media} = $self->{_social_media};
		$vals->{info} = $info;
		$vals->{as_string} = $info->as_string();

		$template->process($filename, $vals, \$rc) ||
			throw Error::Simple($template->error());
	} elsif($filename =~ /\.(html?|txt)$/) {
		open(my $fin, '<', $filename);

		my @lines = <$fin>;

		close $fin;

		$rc = join('', @lines);
	} else {
		throw Error::Simple("Unhandled file type $filename");
	}

	if(($filename !~ /.txt$/) && ($rc =~ /\smailto:(.+?)>/)) {
		unless($1 =~ /^&/) {
			$self->_debug({ message => "Found mailto link $1, you should remove it or use " . obfuscate($1) . ' instead' });
		}
	}

	return $rc;
}

sub as_string {
	my ($self, $args) = @_;

	# TODO: Get all cookies and send them to the template.
	# 'cart' is an example
	unless($args && $args->{cart}) {
		my $purchases = $self->{_info}->get_cookie(cookie_name => 'cart');
		if($purchases) {
			my %cart = split(/:/, $purchases);
			$args->{cart} = \%cart;
		}
	}
	unless($args && $args->{itemsincart}) {
		if($args->{cart}) {
			my $itemsincart;
			foreach my $key(keys %{$args->{cart}}) {
				if(defined($args->{cart}{$key}) && ($args->{cart}{$key} ne '')) {
					$itemsincart += $args->{cart}{$key};
				} else {
					delete $args->{cart}{$key};
				}
			}
			$args->{itemsincart} = $itemsincart;
		}
	}

	my $html = $self->html($args);
	unless($html) {
		return;
	}
	return $self->http() . $html;
}

# my $f = pfopen('/tmp:/var/tmp:/home/njh/tmp', 'foo', 'txt:bin' );
# $f = pfopen('/tmp:/var/tmp:/home/njh/tmp', 'foo');
sub _pfopen {
	my $self = shift;
	my $path = shift;
	my $prefix = shift;
	my $suffixes = shift;

	our $savedpaths;

	my $candidate;
	if(defined($suffixes)) {
		$candidate = "$prefix;$path;$suffixes";
	} else {
		$candidate = "$prefix;$path";
	}
	if($savedpaths->{$candidate}) {
		$self->_debug({ message => "remembered $savedpaths->{$candidate}" });
		return $savedpaths->{$candidate};
	}

	foreach my $dir(split(/:/, $path)) {
		next unless(-d $dir);
		if($suffixes) {
			foreach my $suffix(split(/:/, $suffixes)) {
				$self->_debug({ message => "check for file $dir/$prefix.$suffix" });
				my $rc = "$dir/$prefix.$suffix";
				if(-r $rc) {
					$savedpaths->{$candidate} = $rc;
					return $rc;
				}
			}
		} elsif(-r "$dir/$prefix") {
			my $rc = "$dir/$prefix";
			$savedpaths->{$candidate} = $rc;
			$self->_debug({ message => "using $rc" });
			return $rc;
		}
	}
}

sub _debug {
	my $self = shift;

	if($self->{_logger}) {
		my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
		if($ENV{'REMOTE_ADDR'}) {
			$self->{_logger}->debug("$ENV{'REMOTE_ADDR'}: $params{'message'}");
		} else {
			$self->{_logger}->debug($params{'message'});
		}
	}
}

sub obfuscate {
	map { '&#' . ord($_) . ';' } split(//, shift);
}

sub _append_browser_type {
	my $self = shift;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	if($self->{_logger}) {
		$self->{_logger}->trace('_append_browser_type');
	}

	my $directory = $args{'directory'};

	return unless(defined($directory));

	if($self->{_logger}) {
		$self->{_logger}->debug("_append_browser_type: directory = $directory");
	}
	my $rc;

	if(-d $directory) {
		if($self->{_info}->is_mobile()) {
			$rc = "$directory/mobile:";
		} elsif($self->{_info}->is_search_engine()) {
			$rc = "$directory/search:$directory/web:$directory/robot:";
		} elsif($self->{_info}->is_robot()) {
			$rc = "$directory/robot:";
		}
		$rc .= "$directory/web:";

		$self->_debug({ message => "_append_directory_type: $directory=>$rc" });
		return $rc;
	}

	return '';	# Don't return undef or else the caller may use an uninit variable

}

1;