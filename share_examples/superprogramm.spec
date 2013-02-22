%define __prefix /usr/opt

Summary:superprogramm summary
Name:superprogramm
Version: %{version}
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Release: %{release}
Prefix: %{_prefix}

Requires: python mysql mysql-server

Url: http://superprogramm.com/
License: BSD


%description
Superprogramm description


%prep
if [ -d %{name} ]; then
    echo "Cleaning out stale build directory" 1>&2
    rm -rf %{name}
fi


%build
# rpmbuild/BUILD
mkdir -p %{name}
cp -R %{source0}/src %{name}/
rm -rf %{name}/src/%{name}/.git*
find %{name}/ -type f -name "*.py[co]" -delete

# replace builddir path
find %{name}/ -type f -exec sed -i "s:%{_builddir}:%{__prefix}:" {} \;


%install
# rpmbuild/BUILD
mkdir -p %{buildroot}%{__prefix}/%{name}
mv %{name} %{buildroot}%{__prefix}/

# hack for lib64
rm %{buildroot}%{__prefix}/%{name}/env/lib64; ln -sf %{__prefix}/%{name}/env/lib %{buildroot}%{__prefix}/%{name}/env/lib64

# init.d files for gunicorn, celeryd, celerycam
#%{__install} -p -D -m 0755 %{buildroot}%{__prefix}/%{name}/src/bin/gunicorn.initd.sh %{buildroot}%{_initrddir}/%{name}-gunicorn
#%{__install} -p -D -m 0755 %{buildroot}%{__prefix}/%{name}/src/bin/celeryd.initd.sh %{buildroot}%{_initrddir}/%{name}-celeryd
#%{__install} -p -D -m 0755 %{buildroot}%{__prefix}/%{name}/src/bin/celerycam.initd.sh %{buildroot}%{_initrddir}/%{name}-celerycam

# configs
#mkdir -p %{buildroot}%{_sysconfdir}/%{name}
#%{__install} -p -D -m 0755 %{buildroot}%{__prefix}/%{name}/src/share/django.conf %{buildroot}%{_sysconfdir}/%{name}/django.conf
#%{__install} -p -D -m 0755 %{buildroot}%{__prefix}/%{name}/src/share/gunicorn.conf %{buildroot}%{_sysconfdir}/%{name}/gunicorn.conf

# bin
mkdir -p %{buildroot}%{_bindir}
ln -s %{__prefix}/%{name}/src/bin/manage.sh %{buildroot}%{_bindir}/%{name}


%post
if [ $1 -gt 1 ]; then
    echo "Upgrade"

    # DB
    if %{name} > /dev/null 2>&1; then
        #%{name} syncdb --migrate --noinput
        #%{name} collectstatic
        #%{name} createerrorpages

        #service %{name}-gunicorn restart
        #service %{name}-celeryd restart
        #service %{name}-celerycam restart
    fi
else
    echo "Install"

    /usr/sbin/adduser -M -d %{__prefix}/%{name} -G %{name} -s /sbin/nologin -c 'The %{name} website' %{name} >/dev/null 2>&1 ||:

    #/sbin/chkconfig --list %{name}-gunicorn > /dev/null 2>&1 || /sbin/chkconfig --add %{name}-gunicorn
    #/sbin/chkconfig --list %{name}-celeryd > /dev/null 2>&1 || /sbin/chkconfig --add %{name}-celeryd
    #/sbin/chkconfig --list %{name}-celerycam > /dev/null 2>&1 || /sbin/chkconfig --add %{name}-celerycam

    # logs
    mkdir -p /var/log/%{name}

    echo "Don't forget to setup database and create superuser"
    echo "0. Create database"
    echo "1. Edit configs in /etc/%{name}"
    echo "2. > %{name} syncdb --migrate"
    echo "3. > %{name} collectstatic"
fi


%clean
rm -rf %{buildroot}


%files
%defattr(-,root,root)
#%{_initrddir}/%{name}-gunicorn
#%{_initrddir}/%{name}-celeryd
#%{_initrddir}/%{name}-celerycam
%{__prefix}/%{name}/
#%config(noreplace) %{_sysconfdir}/%{name}/django.conf
#%config(noreplace) %{_sysconfdir}/%{name}/gunicorn.conf
%{_bindir}/%{name}