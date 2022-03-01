#!/bin/bash

ME="$(basename "${BASH_ARGV0}")"

source "${ALLSKY_HOME}/variables.sh"
source "${ALLSKY_CONFIG}/config.sh"
source "${ALLSKY_CONFIG}/ftp-settings.sh"

NOTIFICATION_FILETYPE="${1}"	# filename, minus the extension, since the extension may vary
if [ "${NOTIFICATION_FILETYPE}" = "" ] ; then
	echo -e "${RED}*** ${ME}: ERROR: no file specified.${NC}" >&2
	echo -e "\nUsage: ${ME} notification_file_type [expires_in_seconds]\n" >&2
	exit 1
fi

NOTIFICATION_FILE="${ALLSKY_NOTIFICATION_IMAGES}/${NOTIFICATION_FILETYPE}.${EXTENSION}"
if [ ! -e "${NOTIFICATION_FILE}" ] ; then
	echo -e "${RED}*** ${ME}: ERROR: File '${NOTIFICATION_FILE}' does not exist or is empty!${NC}" >&2
	exit 2
fi

# Optional argument specifying when the ALLSKY_NOTIFICATION_LOG should expire.
EXPIRES_IN_SECONDS="${2:-5}"	# default of 5 seconds

# If a notification image was "recently" posted, don't post this one.
# We'll look at the timestamp of $ALLSKY_NOTIFICATION_LOG (defined in variables.sh) and if it's
# in the future we'll skip the current notification. When the file is updated below.
# it's given a timestamp of NOW + $EXPIRES_IN_SECONDS.
# We will APPEND to the file so we have a record of all notifications since Allsky started.

if [ -f "${ALLSKY_NOTIFICATION_LOG}" ]; then
	# TODO: there has to be a better way to compare the time of a file??
	NOW=$(date +'%Y%m%d%H%M%S')
	FILE_TIME=$(ls -l --time-style="+%Y%m%d%H%M%S" ${ALLSKY_NOTIFICATION_LOG} | awk '{ print $6 }')

	if [ ${FILE_TIME} -gt ${NOW} ]; then
		if [ ${ALLSKY_DEBUG_LEVEL} -ge 3 ]; then
			# File contains:	Notification_type,expires_in_seconds,expiration_time
			RECENT_NOTIFICATION=$(tail -1 "${ALLSKY_NOTIFICATION_LOG}")
			RECENT_TYPE=${RECENT_NOTIFICATION%%,*}
			RECENT_TIME=${RECENT_NOTIFICATION##*,}
			echo "${ME}: Ignoring new '${NOTIFICATION_FILETYPE}'; prior '${RECENT_TYPE}' posted ${RECENT_TIME}."
		fi
		exit 0
	fi
fi

CURRENT_IMAGE="${CAPTURE_SAVE_DIR}/notification-${FULL_FILENAME}"
# Don't overwrite notification image so create a temporary copy and use that.
cp "${NOTIFICATION_FILE}" "${CURRENT_IMAGE}"

# Resize the image if required
if [ "${IMG_RESIZE}" = "true" ]; then
	convert "${CURRENT_IMAGE}" -resize "${IMG_WIDTH}x${IMG_HEIGHT}" "${CURRENT_IMAGE}"
	if [ $? -ne 0 ] ; then
		echo -e "${RED}*** ${ME}: ERROR: IMG_RESIZE failed${NC}"
		exit 3
	fi
fi

# If daytime saving is desired, save the image in today's thumbnail directory if desired
# so the user can see when things changed.
# Don't save in main image directory because we don't want the notification image in timelapses.
# If at nighttime, save them in (possibly) yesterday's directory.
# If during day, save in today's directory.
if [ "${DAYTIME_SAVE}" = "true" -a "${IMG_CREATE_THUMBNAILS}" = "true" ] ; then
	DATE_DIR="${ALLSKY_IMAGES}/$(date +'%Y%m%d')"
	# Use today's folder if it exists, otherwise yesterday's
	[ ! -d "${DATE_DIR}" ] && DATE_DIR="${ALLSKY_IMAGES}/$(date -d '12 hours ago' +'%Y%m%d')"
	THUMBNAILS_DIR="${DATE_DIR}/thumbnails"
	mkdir -p ${THUMBNAILS_DIR}
	THUMB="${THUMBNAILS_DIR}/${FILENAME}-$(date +'%Y%m%d%H%M%S').${EXTENSION}"

	convert "${CURRENT_IMAGE}" -resize "${THUMBNAIL_SIZE_X}x${THUMBNAIL_SIZE_Y}" "${THUMB}"
	if [ $? -ne 0 ] ; then
		echo -e "${YELLOW}*** ${ME}: WARNING: THUMBNAIL resize failed; continuing.${NC}"
	fi
fi

FINAL_IMAGE="${CAPTURE_SAVE_DIR}/${FULL_FILENAME}"	# final resting place - no more changes to it.
mv -f "${CURRENT_IMAGE}" "${FINAL_IMAGE}"	# so web severs can see it.

# Keep track of last notification type and time.
# We don't use the type (at least not yet), but save it anyhow so we can manually look at
# it for debugging purposes.
EXPIRE_TIME=$(date -d "$EXPIRES_IN_SECONDS seconds" +'%Y-%m-%d %H:%M:%S')
echo "${NOTIFICATION_FILETYPE},${EXPIRES_IN_SECONDS},${EXPIRE_TIME}" >> "${ALLSKY_NOTIFICATION_LOG}"
touch --date="${EXPIRE_TIME}" "${ALLSKY_NOTIFICATION_LOG}"

# If upload is true, optionally create a smaller version of the image, either way, upload it.
if [ "${UPLOAD_IMG}" = "true" ] ; then
	if [ "${RESIZE_UPLOADS}" = "true" ]; then
		# Don't overwrite FINAL_IMAGE since the web server(s) may be looking at it.
		TEMP_FILE="${CAPTURE_SAVE_DIR}/resize-${FULL_FILENAME}"
		cp "${FINAL_IMAGE}" "${TEMP_FILE}"		# create temporary copy to resize
		convert "${TEMP_FILE}" -resize "${RESIZE_UPLOADS_SIZE}" -gravity East -chop 2x0 "${TEMP_FILE}"
		if [ $? -ne 0 ] ; then
			echo -e "${RED}*** ${ME}: ERROR: RESIZE_UPLOADS failed${NC}"
			# Leave temporary file for possible debugging.
			exit 4
		fi
		UPLOAD_FILE="${TEMP_FILE}"
	else
		UPLOAD_FILE="${FINAL_IMAGE}"
		TEMP_FILE=""
	fi

	# We're actually uploading $UPLOAD_FILE, but show $NOTIFICATION_FILE in the message since it's more descriptive.
	echo -e "${ME}: Uploading $(basename "${NOTIFICATION_FILE}")"
	"${ALLSKY_SCRIPTS}/upload.sh" --silent "${UPLOAD_FILE}" "${IMAGE_DIR}" "${FULL_FILENAME}" "NotificationImage"
	RET=$?

	# If we created a temporary copy, delete it.
	[ "${TEMP_FILE}" != "" ] && rm -f "${TEMP_FILE}"

	exit ${RET}
fi

exit 0
