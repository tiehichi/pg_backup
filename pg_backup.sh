#!/bin/bash
BAK=$HOME/pgbackup

mkdir -p $BAK

GDrive(){
    while ! result=`gdrive "$@"`; do sleep 1; done
    echo "$result"
}

# backup globals (database names, users, etc)
# get id of PGBAK folder
PGBAK="`GDrive list --no-header -q "name = 'PGBAK' and trashed = false" | grep -o '^[^ ]*'`"

if [ -z "$PGBAK" ]; then
    echo "Create directory PGBAK on google drive"
    PGBAK="`GDrive mkdir PGBAK | head -n 1 | sed 's/^Directory \([^ ]*\) created$/\1/'`"

    if [ -z "$PGBAK" ]; then
        echo "Can't create the PGBAK folder in the Google Drive" >2
        exit 1
    fi
fi

sudo -iu postgres pg_dumpall -g | xz -9 > "$BAK"/globals.sql.xz

# get files ids
GF="`GDrive list --no-header -q "trashed = false" --absolute | grep "PGBAK/globals.sql.xz" | head -n 1 | grep -o '^[^ ]*'`"

if [ -z "$GF" ]; then
    echo "Upload $BAK/globals.sql.xz"
    GDrive upload --no-progress -p "$PGBAK" "$BAK"/globals.sql.xz > /dev/null
else
    # a revision list can be queried as follows:
    # gdrive revision list --no-header "$GF"

    echo "Update PGBAK/globals.sql.xz"
    GDrive update --no-progress "$GF" "$BAK"/globals.sql.xz > /dev/null
fi

# backup all databases individually, in script mode
sudo -iu postgres psql -Atc 'select datname from pg_database order by 1' | grep -vE 'template[0|1]' |\
    while read db; do
        echo "Backing up $db..."
        DBF="$BAK/$db.sql"
        sudo -iu postgres pg_dump -C "$db" | xz -9 -T 4 > "$DBF.xz"

        GF="`GDrive list --no-header -q "trashed = false" --absolute | grep "PGBAK/$db.sql.xz" | head -n 1 | grep -o '^[^ ]*'`"

        if [ -z "$GF" ]; then
            echo "Upload $DBF.xz"
            GDrive upload --no-progress -p "$PGBAK" "$DBF.xz" > /dev/null
        else
            # you can get the revision list as follows:
            # gdrive revision list --no-header "$GF"

            echo "Update PGBAK/$db.sql.xz"
            GDrive update --no-progress "$GF" "$DBF.xz" > /dev/null
        fi
    done

rm -rf $BAK