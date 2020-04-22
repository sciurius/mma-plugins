# Plugin: Rhythm

Generate percussion sequences using ASCII tab data.

## Define grooves

    @rhythm Groove, Seq, Bpm=4, Level=9, RTime=0, RVolume=0, Clear=0, SeqSize=0, Debug=0

This defines a groove according to the `Seq`, with optional values for `RTime` etc.

For example:

    @rhythm G1, Debug=1, Level=3, Clear=1, RTime=3, RVolume=2, \
      Seq=SnareDrum1 |-3-2| KickDrum1 |3-3-|

This is identical to:

```
SeqClear
Begin Drum-SnareDrum1
    Tone SnareDrum1
    RTime 3
    RVolume 2
    Sequence { 2 0 90; 4 0 60 }
End
Begin Drum-KickDrum1
    Tone KickDrum1
    RTime 3
    RVolume 2
    Sequence { 1 0 90; 3 0 90 }
End
DefGroove G1
```
Instead of passing the patterns to `Seq` as a value, you can put them in a macro and pass the macro *name* (not value!) instead. See below.

The commands `SeqClear`, `SeqSize`, `RTime` and `RVolume` are only included if the corresponding argument is set to a non-zero value.

When vertically aligning the percussion patterns it becomes visible how the instruments sound together to play the rhythm. For example this is a typical 4-bar percussion:

```
Kick  |2-------3-------|2-------2-------|2-------3-------|2-------2-------|
Snare |----3-------3---|----3-------3---|----3-------3---|----3-------3---|
HiHat |3-1-3-1-3-1-3-1-|3-1-3-1-3-1-3-1-|3-1-3-1-3-1-3-1-|3-1-3-1-3-1-3-11|
```
This is best done with a (multi-line) macro:

```
MSet 08Beat01
1 |2-------3-------|2-------2-------|2-------3-------|2-------2-------|
2 |----3-------3---|----3-------3---|----3-------3---|----3-------3---|
3 |3-1-3-1-3-1-3-1-|3-1-3-1-3-1-3-1-|3-1-3-1-3-1-3-1-|3-1-3-1-3-1-3-11|
MSetEnd

@rhythm G2, 08Beat01, SeqSize=4, Debug=1, Level=3, Clear=1, RTime=3, RVolume=2

```

## Track usage (defining sequences)

The plugin can be called as a track plugin to set sequences for a track.

    Track @rhythm Seq, Bpm=4, Level=9, Debug=0

or

    Begin Track
       @rhythm Seq, Bpm=4, Level=9, Debug=0
    End

For example:

    Drum-Snare @rhythm |9-9-6-9-|9-6-9--9|

This is identical to:

```
Drum-Snare Sequence { 1 0 90; 2 0 90; 3 0 60; 4 0 90 } \
                    { 1 0 90; 2 0 60; 3 0 90; 4.5 0 90 }
```
## Track usage (defining patterns)

The plugin can also be used to define patterns.

For example:

    Drum  @rhythm Define=Xx, Seq=|9-9-6-9-|

This is identical to:
```
Drum Define Xx 1 0 90; 2 0 90; 3 0 60; 4 0 90
```

## Description of ASCII sequence data

When used to define grooves, the `Seq` argument must contain space separated pairs of _instruments_ and ASCII _sequence data_.

Instruments must be either one of the MMA built-in percussion tones, or a decimal number between 1 and 16. In the latter case Zoom compliant names for tracks and tones are used.

An ASCII sequence consists of one or more _bars_ separated by vertical bars. Each bar is divided into equal divisions, corresponding to the number of characters in the bar. Each division has either a decimal number indicating that the instrument must sound, or a `-` to do nothing.

The number of divisions may be anything, although `4`, `8` and `16` are the most common. If you have a ternary beat, or want to use triads, use a tri-fold, e.g. `12`.

Some examples, assuming 4 beats per bar:

| ASCII      | Sequence                                                            |
| :--------- | :------------------------------------------------------------------ |
| `|6|`      | 1 division, velocity 60 on beat 1 `{ 1 0 60 }`                      |
| `|68|`     | 2 divisions, beat 1 and 3: `{ 1 0 60; 3 0 80 }`                     |
| `|6-8-|`   | 4 divisions, beat 1 and 3: `{ 1 0 60; 3 0 80 }`                     |
| `|6--8|`   | 4 divisions, beat 1 and 4: `{ 1 0 60; 4 0 80 }`                     |
| `|6--8--|` | 6 divisions, beat 1 and 3: `{ 1 0 60; 3 0 80 }`                     |
| `|866---|` | 6 divisions, triplet on beat 1+2 `{ 1 0 80; 1.67 0 60; 2.33 0 60 }` |
| `|-|`      | silence: `Z`                                                        |
| `|*|`      | use currently defined sequence for this bar: `*`                    |
| `||`       | repeat previous sequence: `/`                                       |
| `|6||`     | one bar plus repeat: `{1 0 60 } /`                                  |

If the first bar is empty it will generate a silent bar.

## The Level argument

This indicates the maximum volume level as used in the sequence.
Normally volume levels are `0`..`9`, corresponding to volume 0 (silent) to `90`. Zoom tabs use volumes `0,1,2,3`, so with argument `Level=3` these become full-scale volumes `0,30,60,90`.
