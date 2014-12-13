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
use File::Glob ':glob';
use Hash::Merge;
use Getopt::Long;
use List::Util 'max';
$|++;

sub mc_dir {
  my ($self) = @_;
  if ($ARGV[0]) {
    return Path::Class::Dir->new($ARGV[0]);
  }
  if ($^O eq 'MSWin32') {
      return Path::Class::Dir->new($ENV{USERPROFILE},
                                   "AppData",
                                   "Roaming",
                                   ".minecraft");
  } else {
      return Path::Class::Dir->new(File::HomeDir->my_home, '.minecraft');
  }
}

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

sub read_launcher_profiles {
  my ($self) = @_;

  $self->read_json_file($self->mc_dir->file('launcher_profiles.json'));
}

sub write_json_file {
  my ($self, $filename, $value) = @_;

  $filename->dir->mkpath;

  my $content = to_json($value, {
                                 relaxed => 1, # allow comma at end of list
                                 loose => 1,
                                 allow_singlequote => 1,
                                 allow_barekey => 1,
                                 pretty => 1});
  open my $fh, ">", $filename;
  print $fh $content;
}

sub write_launcher_profiles {
  my ($self, $profiles) = @_;

  $self->write_json_file($self->mc_dir->file('launcher_profiles.json'), $profiles);
}

my $options = {};

my $result = GetOptions($options, 
                        "config=s",
                        "version:i",
                        "serverdir:s"
                       );
if (not $result) {
  die "Couldn't parse options";
}
if (not $options->{config}) {
  die "Must specify at least --config=foo.json";
}

my $pack_info = {};

## config from file:
my $config_all = main->read_json_file($options->{config});
my $pack_version = $options->{version} || max(keys %$config_all);

my $current_pack_info;

my $merger = Hash::Merge->new('RIGHT_PRECEDENT');

for my $ver (0 .. $pack_version) {
  next unless(exists $config_all->{$ver});

  $config_all->{$ver}{pack_version} ||= $ver;
  
  $current_pack_info = $merger->merge(
                                      $current_pack_info,
                                      $config_all->{$ver}
                                     );
}

#Dump $current_pack_info;

my $name = $current_pack_info->{pack_name};
my $ver_id = $current_pack_info->{pack_dir}.$pack_version;

my $game_dir;


if ($options->{serverdir}) {
  $game_dir = Path::Class::Dir->new($options->{serverdir});
} else {
  #my $current_pack_info = $pack_info->{$pack_version};
  $game_dir = main->mc_dir->subdir($current_pack_info->{pack_dir});
  $game_dir->mkpath;
  $game_dir->subdir('mods')->mkpath;
  
  my $profiles = main->read_launcher_profiles;
  #Dump $profiles;
  $profiles->{profiles}{$name}{name} = $name;
  $profiles->{profiles}{$name}{lastVersionId} = $ver_id;
  $profiles->{profiles}{$name}{gameDir} ||= $game_dir . "";
  
  main->write_launcher_profiles($profiles);
  
  # Make version that we told the launcher profile to use.
  
  
  # Vanilla
  my $vanilla_ver = $current_pack_info->{vanilla};
  main->mc_dir->subdir('versions', $ver_id)->mkpath;
  
  copy(main->mc_dir->file('versions', $vanilla_ver, "$vanilla_ver.jar"),
       main->mc_dir->file('versions', $ver_id, "$ver_id.jar")) or die "Copy from versions/$vanilla_ver/$vanilla_ver.jar to versions/$ver_id/$ver_id.jar failed: $!";
  
  # Forge
  my $version_info;
  if ($current_pack_info->{forge}) {
    my $forge_from;
    my $forge_to;
    if ($current_pack_info->{vanilla} ge '1.7') {
	my $vdashf = $current_pack_info->{vanilla}."-".$current_pack_info->{forge};
	$forge_from = "forge-$vdashf-universal.jar";
	# /home/theorb/.minecraft/libraries/net/minecraftforge/forge/1.7.2-10.12.1.1082/forge-1.7.2-10.12.1.1082.jar
	$forge_to   = main->mc_dir->file('libraries', qw<net minecraftforge forge>, $vdashf, "forge-$vdashf.jar");
    } else {
	$forge_from = 'minecraftforge-universal-'.$current_pack_info->{vanilla}."-".$current_pack_info->{forge}.".jar";
	$forge_to   = main->mc_dir->file('libraries', qw<net minecraftforge minecraftforge>, $current_pack_info->{forge}, 'minecraftforge-'.$current_pack_info->{forge}.".jar");
    }
    print "Starting with forge from $forge_from\n";
    
    $forge_to->dir->mkpath;
    copy($forge_from, $forge_to) or die "Can't copy $forge_from to $forge_to: $!";
    
    use Archive::Zip ':ERROR_CODES', ':CONSTANTS';
    my $zip = Archive::Zip->new;
    ($zip->read($forge_from) == AZ_OK) or die "Erorr reading $forge_from: $!";
    $zip->extractMember('version.json', '/tmp/asoidfj');
    
    $version_info = main->read_json_file('/tmp/asoidfj');
    
    $version_info->{id} = $ver_id;
    $version_info->{time} = $current_pack_info->{time};
    $version_info->{releaseTime} = $current_pack_info->{time};
  }
  
  print Dumper $version_info;
  main->write_json_file(main->mc_dir->file('versions', $ver_id, $ver_id . '.json'), $version_info);
}

for my $mod_name (sort {lc $a cmp lc $b} keys %{$current_pack_info->{normalish_mods}}) {
  my $mod = $current_pack_info->{normalish_mods}{$mod_name};
  printf "Doing %s v %s\n", $mod_name, $mod->{version} || "null";

  if (not defined $mod->{filename_pattern}) {
    die "Missing filename pattern for mod $mod_name";
  }

  if ($options->{serverdir} and $mod->{noserver}) {
    $mod->{version} = undef;
  }

  if (not $options->{serverdir} and $mod->{noclient}) {
      $mod->{version} = undef;
  }

  if (not defined $mod->{version}) {
    # FIXME: Should rm previous versions still, just not add new ones.
    # This is the right way to say "this mod removed from this version"
    next;
  }

  my $filename = sprintf($mod->{filename_pattern}, $mod->{version});
  #print "Installing $filename\n";

  my $dest_name = Path::Class::File->new($filename)->basename;
  # FIXME: this goes screwy when the filename pattern already has metacharacters in it -- [1.6.2] is not a terribly odd thing, for example.
  #my $glob = sprintf($mod->{filename_pattern}, "*");
  #$glob = Path::Class::File->new($glob);
  #$glob = $glob->basename;
  my $glob = $mod->{filename_pattern};
  $glob =~ s!^.*/!!;
  $glob = quotemeta($glob);
  $glob =~ s!\\/!/!g;
  $glob =~ s!\\%s!*!g;
  #print "Glob from ".$mod->{filename_pattern}." is $glob\n";

  my $kind_dir;
  if (!$mod->{kind}) {
    $kind_dir = 'mods';
  } elsif ($mod->{kind} eq 'resource') {
    $kind_dir = 'resourcepacks';
  } else {
    die "Don't know where to put kind ".$mod->{kind};
  }

  my @matches = bsd_glob($game_dir->file($kind_dir, $glob),
                         GLOB_ERR | GLOB_LIMIT | GLOB_NOSORT | GLOB_QUOTE);
  my $no_copy;
  for my $match (@matches) {
    $match = Path::Class::File->new($match);
    if (not -e $match) {
      print "Hmm?  $match but not exists?\n";
    } elsif ($match->basename eq $dest_name) {
      print "Found $match, marking already present\n";
      $no_copy++;
    } else {
      print "Deleting wrong version $match\n";
      unlink($match);
    }
  }

  if ($no_copy) {
    print "Skipping copy, already present\n";
  } else {
    copy($filename, $game_dir->subdir($kind_dir))
      or die "Can't copy $filename: $! (try ".$mod->{homepage}.")";
  }


  for my $config_name (keys %{$mod->{config}}) {
    for my $config_key (keys %{$mod->{config}{$config_name}}) {
      if ($config_key eq 'file') {
        my $filename = $game_dir->file($config_name);
        $filename->parent->mkpath;
        open my $fh, ">", $filename;
        print $fh $mod->{config}{$config_name}{$config_key};
      } else {
        die "Unhandled config key $config_key for filename $config_name";
      }
    }
  }
}

#Dump $version_info;

if ($current_pack_info->{tropicraft}) {
  my $v = $current_pack_info->{tropicraft}{version};
  if (-e $game_dir->file("tropicraft_version_$v")) {
    print "Not extracting tropicraft $v, already there\n";
  } else {
    print "Extracting tropicraft $v\n";
    
    
    use Archive::Zip ':ERROR_CODES', ':CONSTANTS';
    
    my $zip  = Archive::Zip->new;
    my $zip_filename = "mods/tropicraft/Tropicraft v$v for Minecraft v1.6.4 Full Build.zip";
    ($zip->read($zip_filename) == AZ_OK) or die "Erorr reading $zip_filename: $!";
    
    ($zip->extractTree('put contents in .minecraft or main server path/mods/',
                       $game_dir->subdir('mods').'/') == AZ_OK) or die "Error extracting tree: $!";

    open my $fh, ">", $game_dir->file("tropicraft_version_$v") or die "Can't open tag file: $!";
    print $fh $v;
    close $fh;
  }
}

if ($current_pack_info->{millenaire}) {
  print "Extracting millenaire\n";

  use Archive::Zip ':ERROR_CODES', ':CONSTANTS';

  my $ver = $current_pack_info->{millenaire}{version};
  my $zip  = Archive::Zip->new;
  my $zip_filename = "live-mods/Millenaire$ver.zip";
  ($zip->read($zip_filename) == AZ_OK) or die "Erorr reading $zip_filename: $!";

  ($zip->extractTree("Millenaire $ver/Put in mods folder/", $game_dir->subdir('mods').'/') == AZ_OK) or die "Error extracting tree: $!";
}

