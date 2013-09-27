#!/usr/bin/perl
use strictures 1;
use LWP::Simple '$ua', 'mirror', 'get';
use HTML::TreeBuilder 5 -noweak;
use HTML::TreeBuilder::XPath;
use Digest::MD5 'md5_hex';
use Encode;

my $mods = [
            {
             name => 'OpenPeripherial',
             url => 'http://www.openperipheral.info/openperipheral/downloads',
            },
            {
             name => 'Magic Bees',
             url => 'http://forestry.sengir.net/forum/viewtopic.php?id=17'
            },
            #{
            # name => 'Thaumic Tinkerer',
            # git => ['https://github.com/Vazkii/ThaumicTinkerer/wiki/Mod-Releases/HEAD', 'Mod-Releases'],
            #},
            {
             name => 'Thaumcraft',
             url => 'http://www.minecraftforum.net/topic/1585216-thaumcraft-305h-updated-172013/',
             filter => 'mcforum',
            },
            {
             name => 'Chococraft',
             url => 'http://www.minecraftforum.net/topic/1119809-152151forge-torojimas-chococraft-288-happiness-distilled-into-avian-form/',
             filter => 'mcforum',
            },
            # billund
            # computercraft
            # mystcraft
            # extrabiomes xl
            # tinker's construct recovery
            {
             name => 'Natura',
             url => 'http://www.minecraftforum.net/topic/1753754-162natura/',
             filter => 'mcforum',
            },
            # thermalexpansion
            {
             name => 'MapWriter',
             url => 'http://www.minecraftforum.net/topic/1570989-152-forge-mapwriter-an-open-source-mini-map/',
             filter => 'mcforum',
            },
            {
             name => 'NEI Addons',
             url => 'http://www.minecraftforum.net/topic/1803460-nei-addons-v181-with-forestry-2280-support/',
             filter => 'mcforum',
            },
            # millinare
            # AE
            {
             name => 'chickenbones',
             url => 'http://www.minecraftforum.net/topic/909223-147152-smp-chickenbones-mods/',
             filter => 'mcforum',
            },
            # extrabees
            {
             name => 'familiars',
             url => 'http://www.minecraftforum.net/topic/931546-162sspsmplan-familiars-new-herobrine-notch-chuck-norris/',
             filter => 'mcforum',
            },
            #name => 'copious-dogs',
            {
             name => 'dalek',
             url => 'http://www.minecraftforum.net/topic/1544398-162-forge-modloader-the-dalek-mod-updated-020913-forge/',
             filter => 'mcforum',
            },
            # buildcraft
            # bibliocraft
            # bibliowoods
            {
             name => 'twilightforest',
             url => 'http://www.minecraftforum.net/topic/561673-162-the-twilight-forest-v1190-updated-to-minecraft-16/',
             filter => 'mcforum',
            },
            {
             name => 'dartcraft',
             url => 'http://www.minecraftforum.net/topic/1686840-162-dartcraft-beta-0205/',
             filter => 'mcforum',
            },
            # emasher's
            # steve's carts
            # dynmap
            # rei's minimap
            # denlib
            # pluginsforforestry
            {
             name => "denoflion's",
             url => 'http://www.minecraftforum.net/topic/1253666-162152forge-denoflions-mods-threads-condensed/',
             filter => 'mcforum',
            },
            # name => 'forge',
            {
             name => "Tinker's Construct",
             url => 'http://www.minecraftforum.net/topic/1659892-15xtinkers-construct/',
             filter => 'mcforum',
            },
            # neiplugins
            # forestry
            {
             name => "Reika's",
             url => 'http://www.minecraftforum.net/topic/1969694-15216forgesmp-reikas-mods/',
             filter => 'mcforum'
            },
           ];

for my $mod (@$mods) {
  my $page = get($mod->{url});
  my $filter = $mod->{filter} || 'data';
  my $data;

  if ($filter eq 'mcforum') {
    my $tree = HTML::TreeBuilder->new_from_content($page);
    $data = $tree->look_down(class => 'post_body')->as_HTML;
  } elsif ($filter eq 'data') {
    $data = encode('utf8', $page);
  }

  my $md5 = md5_hex($data);

  printf "%32s: %s\n", $md5, $mod->{name};
}
