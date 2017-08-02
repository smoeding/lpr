# lpr - send files to a JetDirect compatible printer without using a spooler

This Perl script is a quick hack to use an office printer without setting up a complete spooler system.

The script was written to mimic the `lpr` command that Emacs calls when printing a buffer. Instead of installing a full-blown spooler system it simply connects to a given printer (hardcoded) and submits the job. It also enables duplex printing if a PostScript file is submitted.

See the Pod documentation provided by the script for more details.
