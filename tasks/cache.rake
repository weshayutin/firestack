namespace :cache do

    # uploader to rpm cache
    task :fill_cache => :distro_name do

        cacheurl=ENV["CACHEURL"]
        raise "Please specify a CACHEURL" if cacheurl.nil?
        cache_user=ENV["CACHE_USER"]
        raise "Please specify a CACHE_USER" if cache_user.nil?
        cache_password=ENV["CACHE_PASSWORD"]
        raise "Please specify a CACHE_PASSWORD" if cache_password.nil?
        server_name=ENV['SERVER_NAME']
        server_name = "localhost" if server_name.nil?

        remote_exec %{
ssh #{server_name} bash <<-"EOF_SERVER_NAME"
#{BASH_COMMON}
ls -d *_source || { echo "No RPMS to upload"; exit 0; }

grep -i #{ENV['DISTRO_NAME']} /etc/*release &> /dev/null || { echo "Distro name mismatch. Caching disabled."; exit 0; }

for SRCDIR in $(ls -d *_source) ; do
    PROJECT=$(echo $SRCDIR | cut -d _ -f 1)
    echo Checking $PROJECT

    cd ~/$SRCDIR
    SRCUUID=$(git log -n 1 --pretty=format:%H)
    # If we're not at the head of master then we wont be caching
    [ $SRCUUID != $(cat .git/refs/heads/master) ] && continue

    cd ~/rpm_$PROJECT
    PKGUUID=$(git log -n 1 --pretty=format:%H)
    # NOTE: we allow caching of non-master packagers (el6 for example)
    #[ $PKGUUID != $(cat .git/refs/heads/master) ] && continue

    URL=#{cacheurl}/pkgcache/pkgcache/#{ENV['DISTRO_NAME']}/$PKGUUID/$SRCUUID
    echo Cache : $PKGUUID $SRCUUID

    FILESWEHAVE=$(curl -k $URL 2> /dev/null)
    for file in $(find . -name "*rpm") ; do
        if [[ ! "$FILESWEHAVE" == *$(echo $file | sed -e 's/.*\\///g')* ]] ; then
            echo POSTING $file to $PKGUUID $SRCUUID
            curl -k -u "#{cache_user}:#{cache_password}" -X POST $URL -Ffile=@$file 2> /dev/null || { echo ERROR POSTING FILE ; exit 1 ; }
        fi
    done
done
EOF_SERVER_NAME
        } do |ok, out|
            fail "Cache of packages failed!" unless ok
        end
    end

end


#git clone w/ retry
CACHE_COMMON=%{
# Test if the rpms we require are in the cache allready
# If present this function downloads them to ~/rpms
function download_cached_rpm {
    install_package git

    local DISTRO_NAME="$1"
    local PROJECT="$2"
    local SRC_URL="$3"
    local SRC_BRANCH="$4"
    local SRC_REVISION="$5"
    local PKG_URL="$6"
    local PKG_BRANCH="$7"

    SRCUUID=$SRC_REVISION
    if [ -z $SRCUUID ] ; then
        SRCUUID=$(git ls-remote "$SRC_URL" "$SRC_BRANCH" | cut -f 1)
        if [ -z $SRCUUID ] ; then
            echo "Invalid source URL:BRANCH $SRC_URL:$SRC_BRANCH"
            return 1
        fi
    fi
    PKGUUID=$(git ls-remote "$PKG_URL" "$PKG_BRANCH" | cut -f 1)
    if [ -z $PKGUUID ] ; then
        echo "Invalid package URL:BRANCH $PKG_URL:$PKG_BRANCH"
        return 1
    fi

    echo "Checking cache For $PKGUUID $SRCUUID"
    FILESFROMCACHE=$(curl -k $CACHEURL/pkgcache/pkgcache/$DISTRO_NAME/$PKGUUID/$SRCUUID 2> /dev/null) \
      || { echo "No files in RPM cache."; return 1; }

    mkdir -p "${PROJECT}_cached_rpms"
    for file in $FILESFROMCACHE ; do
        HADFILE=1
        filename="${PROJECT}_cached_rpms/$(echo $file | sed -e 's/.*\\///g')"
        echo Downloading $file -\\> $filename
        curl -k $CACHEURL/pkgcache/$file 2> /dev/null > "$filename" || HADERROR=1
    done

    if [ -z "$HADERROR" -a -n "$HADFILE" ] ; then
        mkdir -p rpms
        cp "${PROJECT}_cached_rpms"/* rpms
        echo "$(echo $PROJECT | tr [:lower:] [:upper:])_REVISION=${SRCUUID:0:7}"
        return 0
    fi
    return 1
}

}
