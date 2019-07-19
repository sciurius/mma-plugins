# We import the plugin utilities
from MMA import pluginUtils as pu

import datetime
from MMA.common import error, warning
from MMA.macro import macros
import MMA.gbl as gbl
import MMA.chordtable as chordtable
from MMA.chords import ChordNotes
from MMA.regplug import plugList, simplePlugs, trackPlugs

# Minimum MMA required version.
pu.setMinMMAVersion(16, 0)

# A short plugin description.
pu.setDescription("Tweaky.")

author = "Johan Vromans"
# A short author line.
pu.setAuthor("Written by {}".format(author))

pu.addArgument( "Chord", "C", "Chord to be processed" )

# We add a small doc. %NAME% is replaced by plugin name.
pu.setPluginDoc("This plugin has been written by Johan Vromans <jvromans@squirrel.nl>")

# This prints help when MMA is called with -I switch.
def printUsage():
    pu.printUsage()

# This is not a track plugin, so we define run(line).
def run(line):

    args = pu.parseCommandLine(line)
    chord = args["Chord"]

    ch = ChordNotes(chord);

    print("Chord: %s (%s %s)" % ( ch.name, ch.tonic, ch.chordType ) )
    print("NoteList: %s" % ' '.join(map(str, ch.noteList)))
    print("ScaleList: %s" % ' '.join(map(str, ch.scaleList)))
    chordlist = chordtable.chordlist
    c = ch.chordType
    print("%s: %s %s" % 
          ( c, tuple(chordlist[c][0]),
            tuple(chordlist[c][1])))

    # print "}"
    notelist = ch.noteList

    print plugList
    print simplePlugs
    print trackPlugs
    
    pu.addCommand("Begin DefChord")
    pu.addCommand("  {}-0 ({}) {}".format(c, ','.join(map(str, notelist)), tuple(chordlist[c][1])) )
    pu.addCommand("  {}-1 ({}) {}".format(c, ','.join(map(str, notelist)), tuple(chordlist[c][1])) )
    pu.addCommand("End")
    pu.sendCommands()
    
