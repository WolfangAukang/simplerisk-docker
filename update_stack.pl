#!/usr/bin/env perl

use strict;
use warnings;

use constant PASSWORD_SIZE => 21;
use constant FILE_PATH => ">stack.yml"; # Adding > to overwrite file

# Taken from https://www.perlmonks.org/?node_id=233023
sub generate_random_password{ join'', @_[ map{ rand @_ } 1 .. shift ] }

sub create_stack_file {
  my ($release, $password) = @_;
  open(FILE, FILE_PATH);
  print FILE "# Compose file generated automatically

version: '3.6'

services:
  simplerisk:
    environment:
    - DB_SETUP=automatic
    - DB_SETUP_PASS=$password
    - SIMPLERISK_DB_HOSTNAME=mysql
    image: simplerisk/simplerisk-minimal:$release
    ports:
    - \"80:80\"
    - \"443:443\"

  mariadb:
    command: mysqld --sql_mode=\"NO_ENGINE_SUBSTITUTION\"
    environment:
    - MYSQL_ROOT_PASSWORD=$password
    image: mysql:8.0

  smtp:
    image: namshi/smtp
";
  close(FILE);
}

sub main {
  if (0+@_ == 1) {
    my $release = $_[0];
    my $password = generate_random_password PASSWORD_SIZE, 'A'..'Z', 'a'..'z', '0'..'9', '_';
    create_stack_file $release, $password
  }
  else {
    if (0+@_ == 0) { print "No release version provided. Aborting."; }
    else { print "Too many arguments provided. It only requires one. Aborting"; }
    exit 1
  }
}

main @ARGV
