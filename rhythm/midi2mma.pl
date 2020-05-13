#!/usr/bin/perl -w

# Author          : Johan Vromans
# Created On      : Tue May 12 07:25:02 2020
# Last Modified By: Johan Vromans
# Last Modified On: Wed May 13 15:20:20 2020
# Update Count    : 58
# Status          : Unknown, Use with caution!

################ Common stuff ################

use strict;
use warnings;

# Package name.
my $my_package = 'Sciurix';
# Program name and version.
my ($my_name, $my_version) = qw( midi2mma 0.01 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $leadin   = 0;		# lead in, beats
my $compress = 0;		# compress tabs (not equally wide)
my $output;			# output
my $percussion_channel = 9;	# channel 10
my $verbose  = 1;		# verbose processing

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test  = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace |= ($debug || $test);
$verbose |= $trace;

################ Presets ################

binmode( STDOUT, ':utf8' );
binmode( STDERR, ':utf8' );

################ The Process ################

use MIDI::Tweaks;

# Map MIDI drum tones to MMA MIDI names.
my %name;
# Map to drum kit names.
my %kits;

fill_midi();

my $o = MIDI::Opus->new( { from_file => $ARGV[0] } );
my $ticks = $o->ticks;		# ticks per beat

# These will be derived from the MIDI data.
my $bpm   = 4;			# beats per measure (tentative)
my $tempo = 120;		# tempo (tentative)

# Accumulated output.
my @out;

# Get beats per measure from first track.
for my $track ( $o->tracks_r->[0] ) {
    for my $e ( $track->events ) {
	if ( $e->[EV_TYPE] eq 'time_signature' ) {
	    $bpm = $e->[2];
	    warn("Time signature = $bpm/", 2**($e->[3]), "\n") if $verbose;
	    next;
	}
	if ( $e->[EV_TYPE] eq 'set_tempo' ) {
	    $tempo = int( 60000000 / $e->[2] );
	    warn("Tempo = $tempo\n") if $verbose;
	}
    }
}

my %used;			# drumtones seen, with step
my $patch = 0;			# drumkit, usually 0 (standard kit)
				# will be derived from the MIDI data.

# Process the tracks.
foreach my $track ( $o->tracks ) {
    my @ev = $track->events;

    # Filter out track with drum channel.
    my $isdrum = 0;
    for ( @ev ) {
	if ( $_->[EV_TYPE] eq 'patch_change' && $_->[EV_CHAN] == $percussion_channel ) {
	    $isdrum++;
	    last;
	}
	last if $_[0];		# not at start
    }
    next unless $isdrum;

    # Convert delta to absolute times.
    $track->delta2time;

    # Collect note_on events per tone.
    my $t;
    for my $e ( @ev ) {
	# Only interested in note_on events.
	if ( $e->[EV_TYPE] eq 'time_signature' ) {
	    $bpm = $e->[2];
	    warn("Time signature = $bpm/", 2**($e->[3]), "\n") if $verbose;
	}
	if ( $e->[EV_TYPE] eq 'patch_change' ) {
	    $patch = $e->[3];
	    printf STDERR ( "Drum kit = %d (%s)\n", $patch,
			    $kits{$patch} || "**Unknown**" ) if $verbose;
	}
	next unless $e->[EV_TYPE] eq 'note_on' && $e->[EV_NOTE_VELO] > 1;
	push( @{ $t->{$e->[EV_NOTE_PITCH]} }, $e );
    }
    my $tpm = $bpm * $ticks;   # ticks per measure

    # Prescan the events to find step size.
    my $_step = 1;
    foreach my $tone ( sort keys %$t ) {
	my $ev = $t->{$tone};
	my $iclock = $leadin * $ticks; # lead in, ticks

	# Find smallest delta to calculate step value.
	my $clock = $iclock;
	my $sd = $tpm;	# max
	foreach ( @$ev ) {
	    my $d = $_->[EV_TIME] - $clock;
	    $clock = $_->[EV_TIME];
	    if ( $d && $d < $sd ) {
		$sd = $d;
		printf STDERR ("Tone %02d, t = %05d, sd = %d\n",
			       $tone, $clock, $sd ) if $trace;
	    }
	}
	my $step = $tpm / $sd;
	unless ( $step == int($step) ) {
	    $step = sprintf("%.0f", 3*$step)
	      if sprintf("%.3f", $step) =~ /\.(333|667)$/;
	    $step = sprintf("%.0f", 4*$step)
	      if sprintf("%.3f", $step) =~ /\.250$/;
	    $step = sprintf("%.0f", 2*$step)
	      if sprintf("%.3f", $step) =~ /\.500$/;
	    unless ( $step == int($step) ) {
		die(sprintf("Tone %02d, step %.3f not integer, ".
			    "needs quantization!\n",
			    $tone, $tpm/$sd ));
	    }
	}
	warn("Tone $tone, smallest delta = $sd, step = $step\n")
	  if $verbose;
	$used{$name{$tone}} = $step;
	$_step = lcm( $_step, $step );
    }

    # Process the events.
    foreach my $tone ( sort keys %$t ) {
	my $ev = $t->{$tone};
	my $iclock = $leadin * $ticks; # lead in, ticks
	my $step = $compress ? $used{$name{$tone}} : $_step;
	my $sd = $tpm / $step;

	# Generate the tabs.
	my $clock = $iclock;
	my $res = "-" x $step;
	my $m = 0;
	for ( @$ev ) {
	    while ( $_->[EV_TIME] >= $iclock + $bpm * $ticks ) {
		push( @{$out[$m]}, fmt_tab( $tone, $res ) );
		$iclock += $tpm;
		$clock = $iclock;
		$res = "-" x $step;
		$m++;
	    }
	    if ( $debug ) {
		printf STDERR ( "%6d: step %2d, velo %d\n",
				$_->[EV_TIME],
				1 + ( $_->[EV_TIME] - $iclock ) / $sd,
				$_->[EV_NOTE_VELO]);
	    }
	    substr( $res, ( $_->[EV_TIME] - $iclock ) / $sd, 1,
		    1 + int( $_->[EV_NOTE_VELO] / 12.8 ) );
	    $clock = $_->[EV_TIME];
	}
	push( @{$out[$m]}, fmt_tab( $tone, $res ) );
    }
}

# Combine and print all.
fmt_mma( \%used, \@out, $patch );

################ Subroutines ################

sub fmt_tab {
    my ( $tone, $tab ) = @_;
    sprintf( "Drum-%-14s \@rhythm  Seq=|%s|", $name{$tone}, $tab );
}

sub fmt_mma {
    my ( $used, $out, $patch ) = @_;

    my $fh;
    if ( $output && $output ne '-' ) {
	open( $fh, '>:utf8', $output )
	  or die("$output: $!\n");
	select($fh);
    }

    print <<EOD;
Plugin Rhythm

// For setting up the instruments.
MSet BeatA
EOD
    for ( sort keys %$used ) {
	printf("%-14s |-|\n", $_ );
    }
    print <<EOD;
MSetEnd

\@rhythm BeatA, BeatA

Tempo $tempo

/**** End Preamble ****/

Groove BeatA

EOD

    printf( "// DrumKit %s\n\n", $kits{$patch} ) if $kits{$patch};
    my $measure = 0;
    for my $m ( @$out ) {
	$measure++;
	for my $seq ( @$m ) {
	    next if $seq =~ /^Drum-(\S+)/ && $seq eq $used->{$1};
	    $used->{$1} = $seq if $1;
	    print( $seq. "\n" );
	}
	printf( "%3d  z\n", $measure );
    }

    if ( $fh ) {
	close($fh) or die("$output: $!\n");
	select(STDOUT);
    }
}

=begin later

# Cute idea, but doesn't work since MMA only honors one After per location.

sub fmt_mma_alt {
    my ( $used, $out ) = @_;
    print <<EOD;
Plugin Rhythm

// For setting up the instruments.
MSet BeatA
EOD
    for ( sort keys %$used ) {
	printf("%-14s |-|\n", $_ );
    }
    print <<EOD;
MSetEnd

\@rhythm BeatA, BeatA

Tempo $tempo

/**** End Preamble ****/

Groove BeatA

EOD

    my $measure = 0;
    for my $m ( @$out ) {
	$measure++;
	for my $seq ( @$m ) {
	    next if $seq =~ /^Drum-(\S+)/ && $seq eq $used->{$1};
	    $used->{$1} = $seq if $1;
	    if ( $measure > 1 ) {
		printf( "After Count=%d %s\n", $measure-1, $seq );
	    }
	    else {
		printf( "%s\n", $seq );
	    }
	}
    }
    printf( "  1  z * %d\n", $measure );
}

=end later

=cut

sub fill_midi {
    # Map MIDI drum tones to MMA MIDI names.
    %name = (
	     # XG extensions.
	     # 13 => "Surdo Mute",
	     # 14 => "Surdo Open",
	     # 15 => "HiQ",
	     # 16 => "WhipSlap",
	     # 17 => "ScratchPush",
	     # 18 => "ScratchPull",
	     # 19 => "FingerSnap",
	     # 20 => "ClickNoise",
	     # 21 => "MetronomeClick",
	     # 22 => "MetronomeBell",
	     # 23 => "SeqClickL",
	     # 24 => "SeqClickR",
	     # 25 => "BrushTap",
	     # 26 => "BrushSwirlL",
	     # 27 => "BrushSlap",
	     # 28 => "BrushSwirlR",
	     # 29 => "SnareRoll",
	     # 30 => "Castanet",
	     # 31 => "SnareL",
	     # 32 => "Sticks",
	     # 33 => "BassDrumL",
	     # 34 => "OpenRimShot",
	     # SG extensions.
	      25 => 'SnareRoll',
	      26 => 'FingerSnap',
	      27 => 'HighQ',
	      28 => 'Slap',
	      29 => 'ScratchPush',
	      30 => 'ScratchPull',
	      31 => 'Sticks',
	      32 => 'SquareClick',
	      33 => 'MetronomeClick',
	      34 => 'MetronomeBell',
	     # Standard GM.
	      35 => 'KickDrum2',
	      36 => 'KickDrum1',
	      37 => 'SideKick',
	      38 => 'SnareDrum1',
	      39 => 'HandClap',
	      40 => 'SnareDrum2',
	      41 => 'LowTom2',
	      42 => 'ClosedHiHat',
	      43 => 'LowTom1',
	      44 => 'PedalHiHat',
	      45 => 'MidTom2',
	      46 => 'OpenHiHat',
	      47 => 'MidTom1',
	      48 => 'HighTom2',
	      49 => 'CrashCymbal1',
	      50 => 'HighTom1',
	      51 => 'RideCymbal1',
	      52 => 'ChineseCymbal',
	      53 => 'RideBell',
	      54 => 'Tambourine',
	      55 => 'SplashCymbal',
	      56 => 'CowBell',
	      57 => 'CrashCymbal2',
	      58 => 'VibraSlap',
	      59 => 'RideCymbal2',
	      60 => 'HighBongo',
	      61 => 'LowBongo',
	      62 => 'MuteHighConga',
	      63 => 'OpenHighConga',
	      64 => 'LowConga',
	      65 => 'HighTimbale',
	      66 => 'LowTimbale',
	      67 => 'HighAgogo',
	      68 => 'LowAgogo',
	      69 => 'Cabasa',
	      70 => 'Maracas',
	      71 => 'ShortHiWhistle',
	      72 => 'LongLowWhistle',
	      73 => 'ShortGuiro',
	      74 => 'LongGuiro',
	      75 => 'Claves',
	      76 => 'HighWoodBlock',
	      77 => 'LowWoodBlock',
	      78 => 'MuteCuica',
	      79 => 'OpenCuica',
	      80 => 'MuteTriangle',
	      81 => 'OpenTriangle',
	     # SG extensions
	      82 => 'Shaker',
	      83 => 'JingleBell',
	      84 => 'Castanets', # XG: BellTree
	      85 => 'MuteSurdo', # XG: --
	      86 => 'OpenSurdo', # XG: --
	    );

    %kits = (  0 => 'Standard',
	     # SG extensions.
	       8 => 'Room',
	      16 => 'Power',
	      24 => 'Electronic',
	      25 => 'Tr808',
	      32 => 'Jazz',
	      40 => 'Brush',
	      48 => 'Orchestra',
	      56 => 'SFX',
	    );
}

sub gcd {
    my ( $x, $y ) = @_;
    while ( $x ) {
	($x, $y) = ($y % $x, $x);
    }
    return $y;
}

sub lcm {
    my ( $x, $y ) = @_;
    ($x && $y) and $x / gcd($x, $y) * $y or 0;
}

=begin later

# Quantisize vector $v with values between min and max (inclusive) to
# 0 .. q-1 (q intervals);

sub quant {
    my ( $v, $q, $max, $min ) = @_;

    unless ( $max ) {
	$max = -1;
	for ( @$v ) {
	    $max = $_ if $_ > $max;
	}
    }
    $min //= 0;

    my $n = $max - $min + 1;
    my @res;

    for ( @$v ) {
	push( @res, int( $_ / $n * $q ) );
    }

    return wantarray ? @res : \@res;
}

=end later

=cut

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally
    my $man = 0;		# handled locally

    my $pod2usage = sub {
        # Load Pod::Usage only if needed.
        require Pod::Usage;
        Pod::Usage->import;
        &pod2usage;
    };

    # Process options.
    GetOptions( 'leadin=i'	=> \$leadin,
		'compress'	=> \$compress,
		'output=s'	=> \$output,
		'channel=i'	=> sub { $percussion_channel = $_[1]-1 },
		'ident'		=> \$ident,
		'verbose+'	=> \$verbose,
		'quiet'		=> sub { $verbose = 0 },
		'trace'		=> \$trace,
		'help|?'	=> \$help,
		'man'		=> \$man,
		'debug'		=> \$debug)
      or $pod2usage->(2);

    if ( $ident or $help or $man ) {
	print STDERR ("This is $my_package [$my_name $my_version]\n");
    }
    if ( $man or $help ) {
	$pod2usage->(1) if $help;
	$pod2usage->(VERBOSE => 2) if $man;
    }

    unless ( @ARGV == 1 ) {
	$pod2usage->(2);
    }
}

__END__

################ Documentation ################

=head1 NAME

midi2mma - extract percussion data from MIDI and write MMA file

=head1 SYNOPSIS

midi2mma [options] midi-file

 Options:
   --leadin=NN		lead in, in beats (not bars!)
   --compress		compress the tabs
   --output=XXX		MMA file to write
   --channel=N		MIDI percussion channel (default 10)
   --ident		shows identification
   --help		shows a brief help message and exits
   --man                shows full documentation and exits
   --verbose		provides more verbose information
   --quiet		runs as silently as possible

=head1 OPTIONS

=over 8

=item B<--leadin=>I<NN>

Lead in, in beats.

Use this if the MIDI input has leadin beats.

=item B<--compress>

Compresses tabs. Normally all tabs are of equal width so it is easy to
see how the intruments work together.

=item B<--output=>I<XXX>

Name of the output file to write with MMA data.

Default is standard output.

=item B<--channel=>I<NN>

Designates the MIDI percussion channel, if not default.

GM standard is channel 10.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<--ident>

Prints program identification.

=item B<--verbose>

Provides more verbose information.
This option may be repeated to increase verbosity.

=item B<--quiet>

Suppresses all non-essential information.

=item I<file>

The MIDI input file to process.

=back

=head1 DESCRIPTION

This program will read the MIDI input file and produce an MMA data
file with identical (or at least very similar) percussion patterns.

The percussion patterns are not defined as grooves, but inserted in
the tracksq so it is easy and straightforward to add your own grooves
and chords.

To run the resultant MMA program, you need to install the B<rhythm>
plugin.

=head2 DETAILS

The program expects that the MIDI input contains one track that starts
with a patch change event for the percussion channel. All other tracks
are ignored (except for the first track that defines tempo and time
signature).

It is currently not possible to process humanized MIDI data.

Tools like iRealPro produce interesting percussion patterns.

=head1 SEE ALSO

L<MIDI>.

https://www.mellowood.ca/mma/

=head1 AUTHOR

Johan Vromans, C<< <jv at cpan.org> >>

=head1 SUPPORT AND DOCUMENTATION

Development of this program takes place on GitHub:
https://github.com/sciurius/mma-plugins

You can find documentation for this tool with the command.

    midi2mma --man

Please report any bugs or feature requests using the issue tracker on
GitHub.

=head1 ACKNOWLEDGEMENTS

Bob van der Poel, for making MMA.

=head1 COPYRIGHT & LICENSE

Copyright 2020 Johan Vromans, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
