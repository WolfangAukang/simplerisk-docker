#!/usr/bin/env perl

use strict;
use warnings;
use File::Path qw(make_path);

my %supported_images = (
	"jammy" => {
		"php_version" => "8.1"
	},
);

sub generate_dockerfile {
	my $release = $_[0];
	foreach my $image (keys %supported_images) {
		make_path("$image");
		my $php_version = $supported_images{$image}{"php_version"};
		open(FILE, ">$image/Dockerfile");
		print FILE "# Dockerfile generated through script

# Using Ubuntu $image image
FROM ubuntu:$image

# Maintained by SimpleRisk
LABEL maintainer=\"Simplerisk <support\@simplerisk.com>\"

# Make necessary directories
RUN mkdir -p /configurations \\
	     /etc/apache2/ssl \\
	     /passwords \\
	     /var/log/supervisor \\
	     /var/lib/mysql \\
	     /var/run/supervisor \\
	     /var/www/simplerisk

# Installing apt dependencies     
RUN dpkg-divert --local --rename /usr/bin/ischroot && \\
    ln -sf /bin/true /usr/bin/ischroot && \\
    apt-get update && \\
    DEBIAN_FRONTEND=noninteractive apt-get -y install apache2 \\
                                                      php \\
                                                      php-mysql \\
                                                      php-json \\
                                                      php-dev \\
                                                      php-ldap \\
                                                      php-mbstring \\
                                                      php-curl \\
                                                      php-zip \\
                                                      php-gd \\
                                                      php-intl \\
                                                      mysql-client \\
                                                      mysql-server \\
                                                      nfs-common \\
                                                      chrony \\
                                                      cron \\
                                                      python-setuptools \\
                                                      vim-tiny \\
                                                      sendmail \\
                                                      openssl \\
                                                      ufw \\
                                                      supervisor && \\
    rm -rf /var/lib/apt/lists

# Create the OpenSSL password
RUN < /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c21 > /passwords/pass_openssl.txt

# Install and configure supervisor
COPY common/supervisord.conf /etc/supervisor/supervisord.conf

# Configure MySQL
RUN sed -i 's/\\[mysqld\\]/\\[mysqld\\]\\nsql-mode=\"NO_ENGINE_SUBSTITUTION\"/g' /etc/mysql/mysql.conf.d/mysqld.cnf

# Configure Apache
COPY common/foreground.sh /etc/apache2/foreground.sh
COPY common/envvars /etc/apache2/envvars
COPY common/000-default.conf /etc/apache2/sites-enabled/000-default.conf
COPY common/default-ssl.conf /etc/apache2/sites-enabled/default-ssl.conf
RUN sed -i 's/\\(upload_max_filesize =\\) .*\\(M\\)/\\1 5\\2/g' /etc/php/$php_version/apache2/php.ini && \\
	sed -i 's/\\(memory_limit =\\) .*\\(M\\)/\\1 256\\2/g' /etc/php/$php_version/apache2/php.ini && \\
	sed -i 's/;.*\\(max_input_vars =\\) .*/\\1 3000/g' /etc/php/$php_version/apache2/php.ini && \\
	sed -i 's/;.*\\(display_errors =\\) .*/\\1 Off/g' /etc/php/$php_version/apache2/php.ini

# Create SSL Certificates for Apache SSL
RUN mkdir -p /etc/apache2/ssl/ssl.crt /etc/apache2/ssl/ssl.key && \\
	openssl genrsa -des3 -passout pass:/passwords/pass_openssl.txt -out /etc/apache2/ssl/ssl.key/simplerisk.pass.key && \\
	openssl rsa -passin pass:/passwords/pass_openssl.txt -in /etc/apache2/ssl/ssl.key/simplerisk.pass.key -out /etc/apache2/ssl/ssl.key/simplerisk.key && \\
	rm /etc/apache2/ssl/ssl.key/simplerisk.pass.key && \\
	openssl req -new -key /etc/apache2/ssl/ssl.key/simplerisk.key -out  /etc/apache2/ssl/ssl.crt/simplerisk.csr -subj \"/CN=simplerisk\" && \\
	openssl x509 -req -days 365 -in /etc/apache2/ssl/ssl.crt/simplerisk.csr -signkey /etc/apache2/ssl/ssl.key/simplerisk.key -out /etc/apache2/ssl/ssl.crt/simplerisk.crt

# Activate Apache modules
RUN phpenmod ldap && \\
	a2enmod headers rewrite ssl && \\
	a2enconf security && \\
	sed -i 's/\\(SSLProtocol\\) all -SSLv3/\\1 TLSv1.2/g' /etc/apache2/mods-enabled/ssl.conf && \\
	sed -i 's/#\\(SSLHonorCipherOrder on\\)/\\1/g' /etc/apache2/mods-enabled/ssl.conf && \\
	sed -i 's/\\(ServerTokens\\) OS/\\1 Prod/g' /etc/apache2/conf-enabled/security.conf && \\
	sed -i 's/\\(ServerSignature\\) On/\\1 Off/g' /etc/apache2/conf-enabled/security.conf

RUN echo %sudo  ALL=NOPASSWD: ALL >> /etc/sudoers && \\
    echo \"$release\" > /tmp/version

# Download SimpleRisk\n";
    my $download_section;
		if ($release =~ "testing") {
    	$download_section = "COPY ./simplerisk/ /var/www/simplerisk
COPY common/simplerisk.sql /simplerisk.sql";
		} else {
			$download_section = "RUN rm -rf /var/www/html && \\
    curl -sL https://github.com/simplerisk/database/raw/master/simplerisk-en-$release.sql > /simplerisk.sql && \\
    curl -sL https://simplerisk-downloads.s3.amazonaws.com/public/bundles/simplerisk-$release.tgz | tar xz -C /var/www\n"			
		}
		print FILE $download_section;
		print FILE "
# Permissions
RUN chown -R www-data: /var/www/simplerisk

# Setting up cronjob
RUN echo \"* * * * * /usr/bin/php -f /var/www/simplerisk/cron/cron.php > /dev/null 2>&1\" >> /etc/cron.d/backup-cron && \\
    chmod 0644 /etc/cron.d/backup-cron && \\
    crontab /etc/cron.d/backup-cron

EXPOSE 80
EXPOSE 443

# Create the start script and set permissions
COPY common/entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh /etc/apache2/foreground.sh

# Data to save
VOLUME [ \"/passwords\", \"/configurations\", \"/var/log\", \"/var/lib/mysql\", \"/etc/apache2/ssl\", \"/var/www/simplerisk\" ]

# Setting up entrypoint
ENTRYPOINT [ \"/entrypoint.sh\" ]

HEALTHCHECK --interval=1m \\
	CMD curl --fail http://localhost || exit 1

# Start Apache and MySQL
CMD [\"/usr/bin/supervisord\", \"-n\", \"-c\", \"/etc/supervisor/supervisord.conf\"]\n";
  	close(FILE)
	}
}

generate_dockerfile @ARGV
