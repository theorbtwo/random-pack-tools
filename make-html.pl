#!/usr/bin/perl
use strictures 1;
use JSON '-support_by_pp';
use Path::Class;
use File::HomeDir;
#use Data::Dump::Streamer 'Dump', 'Dumper';
use Data::Dumper 'Dumper';
use autodie ':all';
use File::Copy;
use LWP::Simple 'mirror';
use Storable 'dclone';
use File::Glob 'bsd_glob';
use Hash::Merge;
use Getopt::Long;
use List::Util 'max';
use Template;
$|++;

my %options;
my $result = GetOptions(\%options,
                        "config:s",
                        "version:i",
                       );
## config from file:
my $config_all = main->read_json_file($options{config});
my $pack_version = $options{version} // max keys %$config_all;

my $current_pack_info;

my $merger = Hash::Merge->new('RIGHT_PRECEDENT');

for my $ver (1 .. $pack_version) {
  next unless(exists $config_all->{$ver});

  $config_all->{$ver}{pack_version} ||= $ver;

  $current_pack_info = $merger->merge(
                                      $current_pack_info,
                                      $config_all->{$ver}
                                     );
}

for my $mod_key (keys $current_pack_info->{normalish_mods}) {
  my $m = $current_pack_info->{normalish_mods}{$mod_key};
  die "No desc for $mod_key" unless defined $m->{desc};
  die "No homepage for $mod_key" unless defined $m->{homepage};
  $m->{upgrade_note} ||= 'no upgrade note';

  if (not defined $m->{version}) {
    # Remove things we want to not be installed.
    delete $current_pack_info->{normalish_mods}{$mod_key};
  }
}



my $tp = Template->new({STRICT => 1});
$tp->process("make-html.tt.html", $current_pack_info,
             $current_pack_info->{pack_dir}.".html")
  or die "Couldn't process template: ".$tp->error;


sub read_json_file {
  my ($self, $json_filename) = @_;

  open my $fh, "<", $json_filename;
  my $content = do {local $/; <$fh>};
  # random.config should be allowed to be quite sloppy.
  # loose allows literal newlines in double-quoted strings.
  from_json($content, {
                       relaxed => 1, # allow comma at end of list
                       loose => 1,
                       allow_singlequote => 1,
                       allow_barekey => 1,
                      });
}

