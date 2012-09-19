#!/bin/bash

# dump-contacts2db.sh
# Version 0.1, 2012-08-19
# Dumps contacts from an Android contacts2.db to stdout in vCard format
# Usage:  dump-contacts2db.sh path/to/contacts2.db > path/to/output-file.vcf
# Dependencies:  sqlite3 / libsqlite3-dev

# Copyright (C) 2012, Stachre
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# expects single argument, path to contacts2.db
if [ "$#" -ne 1 ]
    then echo -e "Dumps contacts from an Android contacts2.db to stdout in vCard format\n"
    echo -e "Usage:  dump-contacts2db.sh path/to/contacts2.db > path/to/output-file.vcf\n"
    echo -e "Dependencies:  sqlite3 / libsqlite3-dev"
    exit 1
fi

# TODO verify specified contacts2.db file exists

# inits
declare -i cur_contact_id=0
declare -i prev_contact_id=0
NEWLINE_QUOTED=`echo -e "'\n'"`
MS_NEWLINE_QUOTED=`echo -e "'\r\n'"`
CONTACTS2_PATH=$1

# store Internal Field Separator
ORIG_IFS=$IFS

# fetch contact data
# TODO order by account, with delimiters if possible
record_set=`sqlite3 $CONTACTS2_PATH "SELECT raw_contacts._id, raw_contacts.display_name, raw_contacts.display_name_alt, mimetypes.mimetype, REPLACE(REPLACE(data.data1, $MS_NEWLINE_QUOTED, '\n'), $NEWLINE_QUOTED, '\n'), data.data2, REPLACE(REPLACE(data.data4, $MS_NEWLINE_QUOTED, '\n'), $NEWLINE_QUOTED, '\n'), data.data7, data.data8, data.data9, data.data10 FROM raw_contacts, data, mimetypes WHERE raw_contacts._id = data.raw_contact_id AND data.mimetype_id = mimetypes._id ORDER BY raw_contacts._id, mimetypes._id, data.data2"`

# modify Internal Field Separator for parsing rows from recordset
IFS=`echo -e "\n\r"`

# iterate through contacts data rows
# use "for" instead of piped "while" to preserve var values post-loop
for row in $record_set
do
    # modify Internal Field Separator for parsing cols from row
    IFS="|"

    i=0

    for col in $row
    do
        i=$[i+1]

        # contact data fields stored in generic value columns
        # schema determined by "mimetype", which varies by row
        case $i in
            1)    # raw_contacts._id
                cur_contact_id=$col
                ;;

            2)    # raw_contacts.display_name
                cur_display_name=$col
                ;;

            3)    # raw_contacts.display_name_alt
                # replace comma-space with semicolon
                cur_display_name_alt=${col/, /\;}
                ;;

            4)    # mimetypes.mimetype
                cur_mimetype=$col
                ;;

            5)    # data.data1
                cur_data1=$col
                ;;

            6)    # data.data2
                cur_data2=$col
                ;;

            7)    # data.data4
                cur_data4=$col
                ;;

            8)    # data.data7
                cur_data7=$col
                ;;

            9)    # data.data8
                cur_data8=$col
                ;;

            10)    # data.data9
                cur_data9=$col
                ;;

            11)    # data.data10
                cur_data10=$col
                ;;

        esac
    done

    # new contact
    if [ $prev_contact_id -ne $cur_contact_id ]
        then if [ $prev_contact_id -ne 0 ]
            # echo cur vcard
            then if [ ${#cur_vcard_note} -ne 0 ]
                then cur_vcard_note="NOTE:"$cur_vcard_note$'\n'
            fi
            cur_vcard=$cur_vcard$cur_vcard_nick$cur_vcard_org$cur_vcard_tel$cur_vcard_adr$cur_vcard_email$cur_vcard_url$cur_vcard_note
            cur_vcard=$cur_vcard"END:VCARD"
            echo $cur_vcard
        fi

        # init new vcard
        cur_vcard="BEGIN:VCARD"$'\n'"VERSION:3.0"$'\n'
        cur_vcard=$cur_vcard"N:"$cur_display_name_alt$'\n'"FN:"$cur_display_name$'\n'
        cur_vcard_nick=""
        cur_vcard_org=""
        cur_vcard_tel=""
        cur_vcard_adr=""
        cur_vcard_email=""
        cur_vcard_url=""
        cur_vcard_im=""
        cur_vcard_note=""
    fi

    # add current row to current vcard
    # again, "mimetype" determines schema on a row-by-row basis
    case $cur_mimetype in
        vnd.android.cursor.item/nickname)
            cur_vcard_nick=$cur_vcard_nick"NICKNAME:"$cur_data1$'\n'
            ;;

        vnd.android.cursor.item/organization)
            cur_vcard_org=$cur_vcard_org"ORG:"$cur_data1$'\n'
            ;;

        vnd.android.cursor.item/phone_v2)
            case $cur_data2 in
                1)
                    cur_vcard_tel_type="HOME,VOICE"
                    ;;

                2)
                    cur_vcard_tel_type="CELL,VOICE,PREF"
                    ;;

                3)
                    cur_vcard_tel_type="WORK,VOICE"
                    ;;

                4)
                    cur_vcard_tel_type="WORK,FAX"
                    ;;

                5)
                    cur_vcard_tel_type="HOME,FAX"
                    ;;

                6)
                    cur_vcard_tel_type="PAGER"
                    ;;

                7)
                    cur_vcard_tel_type="OTHER"
                    ;;

                8)
                    cur_vcard_tel_type="CUSTOM"
                    ;;

                9)
                    cur_vcard_tel_type="CAR,VOICE"
                    ;;
            esac

            cur_vcard_tel=$cur_vcard_tel"TEL;TYPE="$cur_vcard_tel_type":"$cur_data1$'\n'
            ;;

        vnd.android.cursor.item/postal-address_v2)
            case $cur_data2 in
                1)
                    cur_vcard_adr_type="HOME"
                    ;;

                2)
                    cur_vcard_adr_type="WORK"
                    ;;
            esac

            # ignore addresses that contain only country (MS Exchange)
            # TODO validate general address pattern instead
            if [ $cur_data1 != "United States of America" ]
                then cur_vcard_adr=$cur_vcard_adr"ADR;TYPE="$cur_vcard_adr_type":;;"$cur_data4";"$cur_data7";"$cur_data8";"$cur_data9";"$cur_data10$'\n'
                cur_vcard_adr=$cur_vcard_adr"LABEL;TYPE="$cur_vcard_adr_type":"$cur_data1$'\n'
            fi
            ;;

        vnd.android.cursor.item/email_v2)
            cur_vcard_email=$cur_vcard_email"EMAIL:"$cur_data1$'\n'
            ;;

        vnd.android.cursor.item/website)
            cur_vcard_url=$cur_vcard_url"URL:"$cur_data1$'\n'
            ;;

        # TODO handle IM fields with X-GOOGLE-TALK, X-YAHOO, X-MSN, etc.
        # Temporary workaround adds IM field to NOTE 
        vnd.android.cursor.item/im)
            cur_vcard_im="IM: "$cur_data1

            # put IM field at top of note
            if [ ${#cur_vcard_note} -ne 0 ]
                then cur_vcard_note=$cur_vcard_im"\n\n"$cur_vcard_note
                else cur_vcard_note=$cur_vcard_im
            fi
            ;;

        vnd.android.cursor.item/note)
            # "NOTE:" and trailing \n appended when vCard is finished and echoed
            if [ ${#cur_vcard_note} -ne 0 ]
                then cur_vcard_note=$cur_vcard_note"\n\n"$cur_data1
                else cur_vcard_note=$cur_data1
            fi
            ;;
    esac    

    prev_contact_id=$cur_contact_id

    # reset Internal Field Separator for parent loop
    IFS=`echo -e "\n\r"`
done

# set Internal Field Separator to other-than-newline prior to echoing final vcard
IFS="|"

# echo final vcard
if [ ${#cur_vcard_note} -ne 0 ]
    then cur_vcard_note="NOTE:"$cur_vcard_note$'\n'
fi
cur_vcard=$cur_vcard$cur_vcard_nick$cur_vcard_org$cur_vcard_tel$cur_vcard_adr$cur_vcard_email$cur_vcard_url$cur_vcard_note
cur_vcard=$cur_vcard"END:VCARD"
echo $cur_vcard

# restore original Internal Field Separator
IFS=$ORIG_IFS
