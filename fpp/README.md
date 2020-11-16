# Plugin: FPP

Generate Plectrum finger picking sequences using ASCII tab data.


    Plectrum @fpp Pat, Tab, Bpb=4, Q=4, Debug=0

For example


````
MSet pat1
E |--------|
B |--7---7-|
G |-7-7-7-7|
D |--7---7-|
A |--------|
E |9---8---|
MSetEnd
Plectrum @fpp pp1, pat1
````

This expands to:

````
PLECTRUM Define PP1 1.0 0 6:90 ;      \
                    1.5 0 3:70 ;      \
                    2.0 0 2:70 4:70 ; \
					2.5 0 3:70 ;      \
					3.0 0 6:80 ;      \
					3.5 0 3:70 ;      \
					4.0 0 2:70 4:70 ; \
					4.5 0 3:70 
````

It also defines a macro `PP1` that can be used to set this sequence in
songs, for example:

````
$PP1   Em
       Am
SPP2   B7
       Em
````

For convenience, it also defines a macro `PPSetup` that should be
called once per groove to set up the plectrum track.

## Description of ASCII sequence data

When used to define patterns, the `Pat` argument must either contain a
series of space separated ASCII _sequence data_, one for each of the
strings, or the name of a macro that has the data.

An ASCII sequence consists of one _bar_ separated by vertical bars.
The bar is divided into equal divisions, corresponding to the number
of characters in the bar. Each division has either a decimal number
indicating that the string must sound, or a `-` to do nothing.

A leading string name is allowed and ignored.

Usually it is easiest to define a multi-line macro as can be seen in
the introductionary example.

## Hints

Before defining patterns, make sure you set the right `Time`.

Use `mma -e` to see the expanded lines.

