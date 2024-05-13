#!/usr/bin/env perl

use strict;
use warnings;
use File::Path qw(make_path);

my @supported_images = qw(8.1 8.3);

sub generate_dockerfile {
	my $release = $_[0];
	foreach my $image (@supported_images) {
		my $undotted_image = $image;
		$undotted_image =~ s/\.//;
		my $image_dir="php" . $undotted_image;
		make_path("$image_dir");
		open(FILE, ">$image_dir/Dockerfile");
		print FILE "# Dockerfile generated through script
# Using dedicated PHP image with version $image and Apache
FROM php:$image-apache

# Maintained by SimpleRisk
LABEL maintainer=\"Simplerisk <support\@simplerisk.com>\"

WORKDIR /var/www

# Installing apt dependencies     
RUN apt-get update && \\
    apt-get -y install libldap2-dev \\
                       libicu-dev \\
                       libcap2-bin \\
                       libcurl4-gnutls-dev \\
                       libpng-dev \\
                       libzip-dev \\
                       supervisor \\
                       cron \\
                       mariadb-client && \\
    rm -rf /var/lib/apt/lists/*
# Configure all PHP extensions
RUN docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu && \\
    docker-php-ext-install ldap \\
                           mysqli \\
                           pdo_mysql \\
                           curl \\
                           zip \\
                           gd \\
                           intl
# Setting up setcap for port mapping without root and removing packages
RUN setcap CAP_NET_BIND_SERVICE=+eip /usr/sbin/apache2 && \\
    chmod gu+s /usr/sbin/cron && \\
    apt-get -y remove libcap2-bin && \\
    apt-get -y autoremove && \\
    apt-get -y purge

# Copying all files
COPY common/foreground.sh /etc/apache2/foreground.sh
COPY common/envvars /etc/apache2/envvars
COPY common/000-default.conf /etc/apache2/sites-enabled/000-default.conf
COPY common/default-ssl.conf /etc/apache2/sites-enabled/default-ssl.conf
COPY common/entrypoint.sh /entrypoint.sh

# Configure Apache
RUN echo 'upload_max_filesize = 5M' >> /usr/local/etc/php/conf.d/docker-php-uploadfilesize.ini && \\
	echo 'memory_limit = 256M' >> /usr/local/etc/php/conf.d/docker-php-memlimit.ini && \\
	echo 'max_input_vars = 3000' >> /usr/local/etc/php/conf.d/docker-php-maxinputvars.ini && \\
	echo 'log_errors = On' >> /usr/local/etc/php/conf.d/docker-php-error_logging.ini && \\
	echo 'error_log = /dev/stderr' >> /usr/local/etc/php/conf.d/docker-php-error_logging.ini && \\
	echo 'display_errors = Off' >> /usr/local/etc/php/conf.d/docker-php-error_logging.ini && \\
# Create SSL Certificates for Apache SSL
	echo \$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c\${1:-32}) > /tmp/pass_openssl.txt && \\
	mkdir -p /etc/apache2/ssl/ssl.crt /etc/apache2/ssl/ssl.key && \\
	openssl genrsa -des3 -passout pass:/tmp/pass_openssl.txt -out /etc/apache2/ssl/ssl.key/simplerisk.pass.key && \\
	openssl rsa -passin pass:/tmp/pass_openssl.txt -in /etc/apache2/ssl/ssl.key/simplerisk.pass.key -out /etc/apache2/ssl/ssl.key/simplerisk.key && \\
	rm /etc/apache2/ssl/ssl.key/simplerisk.pass.key /tmp/pass_openssl.txt && \\
	openssl req -new -key /etc/apache2/ssl/ssl.key/simplerisk.key -out  /etc/apache2/ssl/ssl.crt/simplerisk.csr -subj \"/CN=simplerisk\" && \\
	openssl x509 -req -days 365 -in /etc/apache2/ssl/ssl.crt/simplerisk.csr -signkey /etc/apache2/ssl/ssl.key/simplerisk.key -out /etc/apache2/ssl/ssl.crt/simplerisk.crt && \\
# Activate Apache modules
	a2enmod headers rewrite ssl && \\
	a2enconf security && \\
	sed -i 's/\\(SSLProtocol\\) all -SSLv3/\\1 TLSv1.2/g' /etc/apache2/mods-enabled/ssl.conf && \\
	sed -i 's/#\\(SSLHonorCipherOrder on\\)/\\1/g' /etc/apache2/mods-enabled/ssl.conf && \\
	sed -i 's/\\(ServerTokens\\) OS/\\1 Prod/g' /etc/apache2/conf-enabled/security.conf && \\
	sed -i 's/#\\(ServerSignature\\) On/\\1 Off/g' /etc/apache2/conf-enabled/security.conf

# Download and extract SimpleRisk, plus saving release version for database reference
RUN rm -rf /var/www/html && \\\n";
			if ($release ne "testing") {
			print FILE "    curl -sL https://simplerisk-downloads.s3.amazonaws.com/public/bundles/simplerisk-$release.tgz | tar xz -C /var/www && \\\n";
		}
		print FILE "    echo $release > /tmp/version
\n"; 
		if ($release eq "testing") {
			print FILE "COPY ./simplerisk/ /var/www/simplerisk
COPY common/simplerisk.sql /var/www/simplerisk/simplerisk.sql\n";
		}
		print FILE "# Creating Simplerisk user on www-data group and setting up ownerships
RUN useradd -G www-data simplerisk && \\
	chown -R simplerisk:www-data /var/www/simplerisk /etc/apache2 /var/run/ /var/log/apache2 && \\
	chmod -R 770 /var/www/simplerisk /etc/apache2 /var/run/ /var/log/apache2 && \\
	chmod 755 /entrypoint.sh /etc/apache2/foreground.sh

# Data to save
VOLUME [ \"/var/log/apache2\", \"/etc/apache2/ssl\", \"/var/www/simplerisk\" ]

# Using simplerisk user from here
USER simplerisk

# Setting up entrypoint
ENTRYPOINT [ \"/entrypoint.sh\" ]

# Ports to expose
EXPOSE 80
EXPOSE 443

HEALTHCHECK --interval=1m \\
	CMD curl --fail http://localhost || exit 1

# Start Apache 
CMD [\"/usr/sbin/apache2ctl\", \"-D\", \"FOREGROUND\"]\n";
 		close(FILE)
	}
}

generate_dockerfile @ARGV
