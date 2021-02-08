#!/usr/bin/perl
#
# Copyright (c) 2017-2021 Stefan Möding <stm@kill-9.net>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#


use strict;
use warnings;

use Getopt::Std;
use IO::Socket::INET;
use File::Temp qw/ :seekable /;


#
# Config
#
my $peer_addr = '192.168.1.251';  # Printer IP
my $peer_port = '9100';           # JetDirect port
my $papersize = 'a4';

# Complete network address for IO::Socket::INET
my $peer = "${peer_addr}:${peer_port}";


#
# Parse options (all optional)
#
# -J job
# -T title
# -P printer
#
my %opts = ();

getopts('J:T:P:', \%opts) or die "lpr: failed to parse arguments";

# Set printer if given on commandline or use default otherwise
my $printer = defined($opts{'P'}) ? $opts{'P'} : 'ps';


#
# Create a temporary file for stdin if no files are given on the commandline
#
if ($#ARGV < 0) {
  # Store filehandle for temporary stdin file in module variable to prevent
  # premature closing of the filehande.
  our $stdin_copy = stdin2file();

  push @ARGV, $stdin_copy->filename;
}


#
# Process all files
#
foreach my $file (@ARGV) {
  my $typ = filetype($file);
  my $out = undef;

  if ($typ eq 'PostScript' && $printer eq 'deskjet') {
    $out  = ps2deskjet($file);
    $file = $out->filename;
  }
  elsif ($typ eq 'Text' && $printer eq 'deskjet') {
    $out  = text2deskjet($file);
    $file = $out->filename;
  }
  elsif ($typ eq 'PostScript' && $printer eq 'ps') {
    $out  = ps2ps($file);
    $file = $out->filename;
  }

  open my $fd, '<', $file or die "lpr: ${out}: $!";
  &spool($peer, $fd);
  close $fd;
}


########################################################################
#
#
#
sub filetype {
  my $file   = shift;
  my $esc    = chr(27);
  my $buffer;

  open my $fd, '<', $file or die "lpr: ${file}: $!";
  read($fd, $buffer, 8);
  close $fd;

  return 'PostScript' if ($buffer =~ /^%!PS/);
  return 'PCL' if ($buffer =~ /^${esc}E/);
  return 'Text';
}

########################################################################
#
#
#
sub ps2deskjet {
  my $psfile = shift;
  my $buffer;
  my $handle = File::Temp->new();

  binmode($handle);

  my @command = ('gs', '-q', '-sDEVICE=deskjet', '-r600', '-P-',
                 '-dBATCH', '-dNOSAFER', '-dNOPAUSE',
                 "-sPAPERSIZE=${papersize}", '-sOutputFile=-', $psfile);

  open my $pipe, '-|', @command or die "lpr: ${psfile}: $!";

  # Copy from pipe output to temporary file
  while ((read($pipe, $buffer, 8192)) != 0) {
    print $handle $buffer;
  }

  close $pipe;

  # Rewind filehandle
  $handle->seek(0, SEEK_SET);

  $handle;
}


########################################################################
#
#
#
sub text2deskjet {
  my $textfile = shift;
  my $buffer;
  my $handle = File::Temp->new();

  binmode($handle);

  my @command = ('gs', '-q', '-sDEVICE=deskjet', '-r600', '-P-',
                 '-dBATCH', '-dNOSAFER', '-dNOPAUSE',
                 "-sPAPERSIZE=${papersize}", '-sOutputFile=-',
                 '--', 'gslp.ps', $textfile);

  open my $pipe, '-|', @command or die "lpr: ${textfile}: $!";

  # Copy from pipe output to temporary file
  while ((read($pipe, $buffer, 8192)) != 0) {
    print $handle $buffer;
  }

  close $pipe;

  # Rewind filehandle
  $handle->seek(0, SEEK_SET);

  $handle;
}


########################################################################
#
#
#
sub ps2ps {
  my $psfile = shift;
  my $esc    = chr(27);
  my $eot    = chr(4);
  my $buffer;
  my $handle = File::Temp->new();

  binmode($handle);

  # Switch to PostScript
  print $handle $esc . '%-12345X@PJL' . " \n";
  print $handle '@PJL SET DUPLEX = ON' . " \n";
  print $handle '@PJL ENTER LANGUAGE = POSTSCRIPT' . " \n";

  open my $fd, '<', $psfile or die "lpr: ${psfile}: $!";

  while ((read($fd, $buffer, 8192)) != 0) {
    print $handle $buffer;
  }

  close $fd;

  # ^D indicates end of PostScript
  print $handle $eot;
  print $handle $esc . '%-12345X';

  # Rewind filehandle
  $handle->seek(0, SEEK_SET);

  $handle;
}

########################################################################
#
# stdin2file subroutine
#
sub stdin2file {
  my $buffer;
  my $handle = File::Temp->new();

  binmode($handle);

  # Copy from stdin to temporary file
  while ((read(STDIN, $buffer, 8192)) != 0) {
    print $handle $buffer;
  }

  # Rewind filehandle
  $handle->seek(0, SEEK_SET);

  $handle;
}


########################################################################
#
# spool subroutine
#
sub spool {
  my $peer    = shift;
  my $handle  = shift;
  my $dry_run = 0;
  my $buffer;

  if ($dry_run == 1) {
    open my $out, '>', '/tmp/lpr.out' or die "lpr: $!";

    while ((read($handle, $buffer, 8192)) != 0) {
      print $out $buffer;
    }

    close $out;
  }
  else {
    # Push data to raw printer port
    my $socket = new IO::Socket::INET(PeerAddr => $peer, Proto => 'tcp');

    die "lpr: can't connect to printer: $!" unless $socket;

    while ((read($handle, $buffer, 8192)) != 0) {
      print $socket $buffer;
    }

    # Close socket
    shutdown($socket, 1);
    $socket->close();
  }
}

exit 0;

__END__

=pod

=encoding utf-8

=head1 NAME

lpr - print directly to a JetDirect compatible network printer

=cut

=head1 SYNOPSIS

B<lpr>

B<lpr> [foo.ps] [bar.txt] [...]

=head1 DESCRIPTION

The B<lpr> command prints documents on a network printer. It uses a hardcoded
network address and port number to connect directly to the printer. No local
spooler (e.g. lpd or cups) needs to be available.

The B<lpr> commands detects if a document containing PostScript is printed
and will automatically configure the printer to use duplex printing in this
case.

=head1 OPTIONS

=over 8

=item B<-P>I<printer>

The printer name. Accepted for backward compatibility; this option does not
do anything.

=item B<-T>

The title for the print job. Accepted for backward compatibility; this option
does not do anything.

=item B<-J>

The jobname for the print job. Accepted for backward compatibility; this
option does not do anything.

=back

=head1 DIAGNOSTICS

=over 4

=item failed to parse arguments

The command does not understand the options given on the command line.

=item can't open F<file>

The file name given on the command line could not be opened.

=item nothing to print

Nothing was read on standard input so there is nothing to print.

=item can't connect to printer

The connection to the printer has failed. It may be switched off or the
configured IP address and port number do not belong to the correct printer.

=back

=head1 EXAMPLES

    lpr foo.ps
    lpr bar.txt

=head1 BUGS

The printer name and port are hardcoded.

=head1 AUTHOR

Stefan Möding - L<stm@kill-9.net>

=cut
