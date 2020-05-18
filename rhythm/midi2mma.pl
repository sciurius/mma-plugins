#!/usr/bin/perl -w

# Author          : Johan Vromans
# Created On      : Tue May 12 07:25:02 2020
# Last Modified By: Johan Vromans
# Last Modified On: Mon May 18 08:39:09 2020
# Update Count    : 237
# Status          : Unknown, Use with caution!

################ Common stuff ################

use strict;
use warnings;

# Package name.
my $my_package = 'Sciurix';
# Program name and version.
my ($my_name, $my_version) = qw( midi2mma 0.04 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $leadin;			# lead in, beats
my $output;			# output
my $utempo;			# user override tempo
my $seqsize = 1;		# seqsize
my %sections;			# sections, if any
my $after;			# use After for commands
my $play;			# play using mma
my $tabs = 1;			# use tabs where possible
my $stepmax = 48;		# max step before fallback
my $stepmin = 1;		# min step
my $quant = 0;			# quantizise
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
my $bpm   = 4;			# beats per measure
my $bu    = 4;			# quarter notes
my $tempo = 120;		# tempo (tentative)

# Accumulated output.
my @out;

# Get beats per measure from first track.
for my $track ( $o->tracks_r->[0] ) {
    for my $e ( $track->events ) {
	if ( $e->[EV_TYPE] eq 'time_signature' ) {
	    $bpm = $e->[2];
	    $bu = 2**($e->[3]);
	    warn("Time signature = $bpm/$bu\n") if $verbose;
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

    # Filter out track with drum channel.
    my $isdrum = 0;
    for ( $track->events ) {
	last if $_[0];		# not at start
	if ( $_->[EV_TYPE] eq 'patch_change' && $_->[EV_CHAN] == $percussion_channel ) {
	    $isdrum++;
	    last;
	}
    }
    next unless $isdrum;

    # Convert delta to absolute times.
    $track->delta2time;

    if ( $quant ) {
	$_->[EV_TIME] = $quant * int( $_->[EV_TIME] / $quant )
	  for $track->events;
    }
    my @ev = $track->events;

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
    my $_m = 0;
    my $e_first;
    foreach my $tone ( sort keys %$t ) {
	my $ev = $t->{$tone};
	my $iclock = defined($leadin) ? $leadin * $ticks : 0;

	# Find smallest delta to calculate step value.
	my $clock = $iclock;
	my $sd = $tpm;	# max
	foreach ( @$ev ) {
	    $e_first //= $_->[EV_TIME];
	    $e_first = $_->[EV_TIME] if $e_first > $_->[EV_TIME];
	    my $d = $_->[EV_TIME] - $clock;
	    while ( $d > $tpm ) {
		$d -= $tpm;
	    }
	    $clock = $_->[EV_TIME];
	    if ( $d && $d < $sd ) {
		$sd = gcd( $sd, $d );
		printf STDERR ("Tone %02d, t = %05d, sd = %d\n",
			       $tone, $clock, $sd ) if $trace;
	    }
	}

	my $step = $tabs ? $tpm / $sd : $tpm;
	if ( $tabs && $step > $stepmax ) {
	    warn(sprintf( "Tone %02d, step %d too large, ".
			  "falling back to sequence!\n",
			  $tone, $step ));
	    $sd = 1;
	    $step = $tpm;
	}
	warn("Tone $tone, smallest delta = $sd, step = $step\n")
	  if $trace;
	$used{$tone} = $step < $stepmin ? $stepmin : $step;
	$_step = lcm( $_step, $step ) unless $step == $tpm;
	$_m = $clock if $clock > $_m;
    }

    unless ( $e_first ) {
	print STDERR ("No events? Skipped...\n" );
	last;
    }
    printf STDERR ( "First event at %d (%g beats)\n",
		    $e_first, $e_first/$ticks ) if $verbose;
    unless ( defined $leadin ) {
	$leadin = int($e_first/$ticks);
	warn("Lead-in set to $leadin beats\n") if $leadin && $verbose;
    }
    warn("Last event at $_m\n") if $trace;
    $_m = 2 + int( ($_m - $leadin * $ticks - 1) / $tpm );
    warn("Number of measures = $_m\n") if $verbose;

    # Process the events.
    foreach my $tone ( sort keys %$t ) {
	my $ev = $t->{$tone};
	my $iclock = $leadin * $ticks; # lead in, ticks
	my $step = $used{$tone} == $tpm ? $tpm : ($used{$tone} = $_step);
	my $sd = $tpm / $step;

	my $clock = $iclock;
	my $res;
	if ( $sd == 1 ) {
	    $res = "";
	    # Prefill with empty measures.
	    $out[$_]->{$tone} = "z" for 0..$_m-1;
	}
	else {
	    $res = "-" x $step;
	    # Prefill with empty measures.
	    $out[$_]->{$tone} = $res for 0..$_m-1;
	}

	# Generate the tabs.
	my $m = 0;
	for ( @$ev ) {
	    while ( $_->[EV_TIME] >= $iclock + $bpm * $ticks ) {
		$out[$m]->{$tone} =
		  $sd == 1
		  ? $res ? "{ $res }" : "z"
		  : $res;
		$m++;
		$iclock += $tpm;
		$clock = $iclock;
		$res = $sd == 1 ? "" : ("-" x $step);
	    }
	    if ( $debug ) {
		printf STDERR ( "%6d: step %.2f, velo %d\n",
				$_->[EV_TIME],
				1 + ( $_->[EV_TIME] - $iclock ) / $sd,
				$_->[EV_NOTE_VELO]);
	    }
	    my $v = 1 + int( $_->[EV_NOTE_VELO] / (128/9) );
	    if ( $sd == 1 ) {
		$res .= "; " if $res;
		$res .= sprintf( "%g 0 %d",
				 1 + ( $_->[EV_TIME] - $iclock ) / $ticks,
				 $v * 10 );
	    }
	    else {
		substr( $res, ( $_->[EV_TIME] - $iclock ) / $sd, 1, $v );
	    }
	    $clock = $_->[EV_TIME];
	}
	$out[$m]->{$tone} = $sd == 1 ? $res ? "{ $res }" : "z" : $res;
    }

    # Only one drum track.
    last;
}

# Combine and print all.
fmt_mma( \%used, \@out, $patch ) if %used;

################ Subroutines ################

sub fmt_tab {
    my ( $tone, $tab, $seq ) = @_;
    return sprintf( "Drum-%-14s \@rhythm  Seq=|%s|", $name{$tone}, $tab ) if $tab;
    sprintf( "Drum-%-14s Sequence %s", $name{$tone}, $seq ) if $seq;
}

sub fmt_mma {
    my ( $used, $out, $patch ) = @_;

    my $fh;
    if ( $play ) {
	open( $fh, '|-:utf8', "mma", "-P", "/dev/stdin" )
	  or die("mma: $!\n");
	select($fh);
    }
    elsif ( $output && $output ne '-' ) {
	open( $fh, '>:utf8', $output )
	  or die("$output: $!\n");
	select($fh);
    }

    print( "Plugin Rhythm\n\n") if $tabs;
    print <<EOD;
Time $bpm/$bu
SeqClear
SeqSize $seqsize

// Setting up the instruments.
EOD
    for ( sort keys %$used ) {
	printf("Drum-%-14s Tone %s\n", $name{$_}, $name{$_} );
    }
    print <<EOD;

DefGroove Dummy

Tempo @{[$utempo||$tempo]}

/**** End Preamble ****/

Groove Dummy

EOD

    printf( "Tweaks DrumKit=%s\n\n", $kits{$patch} ) if $kits{$patch};

    my %prev;
    # Start with empty.
    foreach ( keys %$used ) {
	$prev{$_} = ''; next;
	$prev{$_} = "-" x $used->{$_};
    }
    my $tpm = $bpm * $ticks;   # ticks per measure

#    while ( @$out % $seqsize ) {
#	push( @$out, { map { $_ => $out->[-1]->{$_} } keys(%$used) } );
#    }


    %sections = ( '' => 1 ) unless %sections;
    my @s = sort { $sections{$a} <=> $sections{$b} } keys(%sections);

    for ( my $si = 0; $si < @s; $si++ ) {
	my $mmin = $sections{$s[$si]};
	my $mmax = $si+1 < @s ? $sections{$s[$si+1]}-1 : @out;
	if ( $s[$si] ne '' ) {
	    warn("Section $s[$si]: start=$mmin, end=$mmax\n") if $verbose;
	    printf( "// Section %s, measures %d - %d\n",
		    $s[$si], $mmin, $mmax );
	}
	for ( my $measure = $mmin-1; $measure < $mmax; $measure += $seqsize ) {
	    my $m = $out[$measure];
	    my $ss = $seqsize;
	    for my $tone ( sort keys %$m ) {
		my $sd = $used->{$tone} == $tpm;
		my $seq = $m->{$tone};
		my $prseq = $seq;
		for ( my $i = 1; $i < $seqsize; $i++ ) {
		    $ss = $i, last if $measure+$i >= $mmax;
		    if ( $sd ) {
			$seq .= $out[$measure+$i]->{$tone} ne $prseq
			  ? " " . $out[$measure+$i]->{$tone} : " /";
		    }
		    else {
			$seq .= '|' . $out[$measure+$i]->{$tone};
		    }
		}
		$seq =~ s;(\s+/)+;; if $sd == 1;
		next if !$debug && $seq eq $prev{$tone};
		$prev{$tone} = $seq;
		printf( "After Count=%-3d ",
			$measure-$mmin+1 ) if $after && $measure>$mmin-1;
		print( fmt_tab( $tone, $sd ? ( undef, $seq ) : $seq ), "\n" );
	    }
	    print( mma_bar( $measure, $ss ), "\n") unless $after;
	}
	print( mma_bar( $mmin-1, $mmax-$mmin+1 ), "\n") if $after;
	print("\n");
    }

    if ( $fh ) {
	close($fh) or die("$output: $!\n");
	select(STDOUT);
    }
}

sub mma_bar {
    my ( $n, $repeat ) = @_;
    sprintf( "%3d  z%s", $n+1, $repeat > 1 ? " * $repeat" : "" );
}

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
	      16 => 'Power',	# aka Rock
	      24 => 'Electronic',
	      25 => 'Tr808',	# aka Synth1
	      32 => 'Jazz',
	      40 => 'Brush',
	      48 => 'Orchestra',
	      56 => 'SFX',
	       # Misc. extensions.
	       1 => 'Standard2',
	      30 => 'Synth2',
	      64 => 'HipHop1',
	      65 => 'HipHop2',
	      66 => 'Techno1',
	      67 => 'Techno2',
	      68 => 'Dance1',
	      69 => 'Dance2',
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
		'output=s'	=> \$output,
		'channel=i'	=> sub { $percussion_channel = $_[1]-1 },
		'seqsize=i'	=> \$seqsize,
		'tempo=i'	=> \$utempo,
		'section|s=i%'	=> \%sections,
		'after'		=> \$after,
		'tabs!'		=> \$tabs,
		'stepmax=i'	=> \$stepmax,
		'stepmin=i'	=> \$stepmin,
		'quant=i'	=> \$quant,
		'play|P'	=> \$play,
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
   --output=XXX		MMA file to write
   --tempo=NNN		tempo (overrides MIDI tempo)
   --seqsize=N		SeqSize for patterns
   --channel=NN		MIDI percussion channel (default 10)
   --after		use MMA 'After' command to set the patterns
   --[no]tabs		use tabs if possible, otherwise sequences
   --stepmax=NN         max step before falling back to sequence
   --stepmin=NN         minimal step (default 8)
   --quant=NN		quantisize times (use 5, or 10)
   --section=XX=NN	define section XX to start at measure NN
   --play -P		play the file with MMA
   --ident		shows identification
   --help		shows a brief help message and exits
   --man                shows full documentation and exits
   --verbose		provides more verbose information
   --quiet		runs as silently as possible

=head1 OPTIONS

=over 8

=item B<--leadin=>I<NN>

Lead in, in beats.

Use this if the MIDI input has leadin beats and the number of leadin
beats is not correctly detected.

Note that the leadin is counted in beats, not measures.

=item B<--tempo=>I<NNN>

Overrides the tempo setting from the MIDI file.

=item B<--seqsize=>I<N>

Uses the given SeqSize for the patterns. Default is 1.

=item B<--output=>I<XXX>

Name of the output file to write with MMA data.

Default is standard output.

=item B<--channel=>I<NN>

Designates the MIDI percussion channel, if not default.

GM standard is channel 10.

=item B<--stepmax=>I<NN>

The maximum value for the tab steps before falling back to sequences.

Default is 48.

=item B<--stepmin=>I<NN>

The minmum value for the tab steps.

Default is 8.

=item B<--quant=>I<NN>

Quantisize event times by truncating to I<NN> ticks.

Sensible values are 4 to 10. With tick size of 480, a 1/128th note
corresponds to 15 ticks.

=item B<--section=>I<XXX>B<=>I<NNN>

Defines section I<XXX> to start at measure I<NNN>.

This may be given multiple times.

First measure is 1.

=item B<--tabs>  B<--notabs>

By default midi2mma graphically represents the patterns using tabs.
These are processed in MMA by the B<Rhythm> plugin.

If a sequence cannot be represented within a preset maximum of tab
steps, an MMA C<Sequence> will be used instead.

With B<--notabs> the program will always use C<Sequence> commands.

See also B<--stepmax>.

=item B<--stepmax=>I<NN>

The maximum number of tab steps before falling back to C<Sequence> commands.

Default is 48.

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

=head1 BUGS AND DEFICIENCIES

Surprising MIDI files may generate surprising results.

Not all MIDI data can be processed at this time.

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
