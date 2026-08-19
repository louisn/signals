package com.naberconsulting.signals.capture

/**
 * Classifies a BLE advertisement as a known tracker tag ("smart tag") from
 * its advertised signatures. Ported from the iOS SignalKit classifier and
 * kept dependency-free so it's unit-testable on the plain JVM.
 *
 * Best-effort: it identifies the tag *ecosystem*, not the individual tag --
 * these products rotate their advertised identifiers by design. Apple Find My
 * accessories advertise only manufacturer data (no service UUID).
 */
enum class TrackerTagType(val wire: String) {
    APPLE_FIND_MY("apple_find_my"),
    TILE("tile"),
    SAMSUNG_SMARTTAG("samsung_smarttag"),
    CHIPOLO("chipolo"),
    GOOGLE_FIND_MY_DEVICE("google_find_my_device"),
}

object TrackerTagClassifier {
    private const val APPLE_COMPANY_ID_LO = 0x4C
    private const val APPLE_COMPANY_ID_HI = 0x00
    private const val APPLE_FIND_MY_PAYLOAD_TYPE = 0x12
    /// Length byte of the "separated" offline-finding frame (0x19 = 25 bytes,
    /// the rotating public key). The "nearby" frame is far shorter (~0x02).
    private const val APPLE_FIND_MY_SEPARATED_MIN_LEN = 0x19
    private const val EDDYSTONE_FMDN_FRAME_TYPE = 0x40

    private val serviceUuidTags = mapOf(
        "FEED" to TrackerTagType.TILE,
        "FD5A" to TrackerTagType.SAMSUNG_SMARTTAG,
        "FE33" to TrackerTagType.CHIPOLO,
    )

    data class Advertisement(
        /** Raw Bluetooth manufacturer-specific data, company-id bytes first. */
        val manufacturerData: ByteArray?,
        /** Advertised 16-bit service UUIDs, as uppercase hex (e.g. "FEED"). */
        val serviceUuids: List<String>,
        /** Service data keyed by 16-bit service UUID hex. */
        val serviceData: Map<String, ByteArray>,
    )

    fun classify(ad: Advertisement): TrackerTagType? {
        classifyByServiceUuid(ad.serviceUuids)?.let { return it }
        if (isAppleFindMySeparated(ad.manufacturerData)) return TrackerTagType.APPLE_FIND_MY
        if (isGoogleFindMyDevice(ad.serviceData)) return TrackerTagType.GOOGLE_FIND_MY_DEVICE
        return null
    }

    private fun classifyByServiceUuid(uuids: List<String>): TrackerTagType? =
        uuids.firstNotNullOfOrNull { serviceUuidTags[it.uppercase()] }

    /**
     * A *separated* Find My device -- an unattended tracker broadcasting its
     * rotating public key while away from its owner. Keyed on Apple company id
     * + offline-finding type (0x12) + the long "separated" length byte.
     *
     * Deliberately excludes the short "nearby" 0x12 frame: that is broadcast
     * by *every* Apple device participating in the Find My network (iPhones,
     * Macs, AirPods near their owner), so flagging it produced huge false-
     * positive "tracker" counts from ordinary ambient Apple devices. Other
     * Apple types (AirPods pairing 0x07, Handoff 0x0C) are excluded too.
     */
    private fun isAppleFindMySeparated(manufacturerData: ByteArray?): Boolean {
        val data = manufacturerData ?: return false
        if (data.size < 4) return false
        val isFindMy = (data[0].toInt() and 0xFF) == APPLE_COMPANY_ID_LO &&
            (data[1].toInt() and 0xFF) == APPLE_COMPANY_ID_HI &&
            (data[2].toInt() and 0xFF) == APPLE_FIND_MY_PAYLOAD_TYPE
        return isFindMy && (data[3].toInt() and 0xFF) >= APPLE_FIND_MY_SEPARATED_MIN_LEN
    }

    /**
     * Google's Find My Device network piggybacks on the Eddystone service UUID
     * (0xFEAA) with its own frame type, distinct from classic Eddystone frames
     * (0x00/0x10/0x20/0x30).
     */
    private fun isGoogleFindMyDevice(serviceData: Map<String, ByteArray>): Boolean {
        val frame = serviceData.entries.firstOrNull { it.key.uppercase() == "FEAA" }?.value ?: return false
        val frameType = frame.firstOrNull()?.toInt()?.and(0xFF) ?: return false
        return frameType == EDDYSTONE_FMDN_FRAME_TYPE
    }
}
