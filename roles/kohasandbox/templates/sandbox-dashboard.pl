#!/usr/bin/perl

use Data::Printer;
use Git::Repository qw(Log);
use Git::Repository::Log;
use YAML qw( LoadFile );
use LWP::Simple;
use Template;
use JSON;
use DBI;

# Create DBI handle to sandbox stats file
my $config_filepath = '/home/vagrant/config.yaml';
my $conf            = LoadFile($config_filepath);
my $db_driver       = $conf->{database}{driver} || q|mysql|;
my $db_name         = $conf->{database}{name};
my $db_port         = $conf->{database}{port} || 3306;
my $db_host         = $conf->{database}{host};
my $db_user         = $conf->{database}{user};
my $db_passwd       = $conf->{database}{passwd};
my $dbh =
  DBI->connect( "DBI:$db_driver:dbname=$db_name;host=$db_host;port=$db_port",
    $db_user, $db_passwd, { 'RaiseError' => $ENV{DEBUG} ? 1 : 0 } )
  or die $DBI::errstr;
my $query =
q{SELECT * FROM stats WHERE action = 'apply' AND instance = ? ORDER BY id DESC LIMIT 1};
my $sth = $dbh->prepare($query);

## Get info about sandboxes
my @sandbox_names = `/usr/sbin/koha-list`;
chomp @sandbox_names;

my @sandboxes;
foreach my $s (@sandbox_names) {
    next if $s eq 'kohadev';

    my $sandbox;
    $sandbox->{name} = $s;

    # Get last usage
    $sth->execute( $s . '_tmp' );
    $sandbox->{last_usage} = $sth->fetchrow_hashref;

    # Get URLs
    $sandbox->{url_staff} = "http://staff.$s.sandbox.bywatersolutions.com/";
    $sandbox->{url_opac}  = "http://catalog.$s.sandbox.bywatersolutions.com/";

    # Get last git commit
    my $r = Git::Repository->new( work_tree => "/var/lib/koha/$s/kohaclone", );
    my $cmd  = Git::Repository::Command->new($r);
    my $iter = Git::Repository::Log::Iterator->new( $r, 'HEAD~10..' );
    my $log  = $iter->next;
    $sandbox->{last_commit}->{$_} = $log->$_ for qw( commit author message );

    # Get Koha version
    # Try looking up version in the modern way, fail to legacy way
    eval { require "/var/lib/koha/$s/kohaclone/Koha.pm" };
    if ($@) {
        eval { require "/var/lib/koha/$s/kohaclone/Koha.pm" };
        if ($@) {
            eval { require "/var/lib/koha/$s/kohaclone/kohaversion.pl"; };

            if ($@) {
                die "Cannot find a way to get Koha version for sandbox '$s'";
            }

            eval { $sandbox->{version} = kohaversion() };
        }
        else {
            eval { $sandbox->{version} = Koha::version() };
        }
    }
    else {
        eval { $sandbox->{version} = Koha::version() };
    }

    push( @sandboxes, $sandbox );
}

## Get info about bugs
my $needs_signoff_url =
q{https://bugs.koha-community.org/bugzilla3/rest/bug?product=Koha&include_fields=id,summary,assigned_to,creation_time&limit=10&status=Needs%20Signoff};
my $needs_signoff      = get($needs_signoff_url);
my $needs_signoff_data = from_json($needs_signoff);

my $signed_off_url =
q{https://bugs.koha-community.org/bugzilla3/rest/bug?product=Koha&include_fields=id,summary,assigned_to,creation_time&limit=10&status=Signed%20Off};
my $signed_off      = get($signed_off_url);
my $signed_off_data = from_json($signed_off);
p $signed_off_data;

my $tt = Template->new(
    {
        INCLUDE_PATH => '/usr/lib/cgi-bin',
    }
) || die "$Template::ERROR\n";

print qq(Content-type: text/html\n\n);
$tt->process(
    'sandbox-dashboard.tt',
    {
        sandboxes     => \@sandboxes,
        needs_signoff => $needs_signoff_data,
        signed_off    => $signed_off_data,
    }
) || die $tt->error(), "\n";
