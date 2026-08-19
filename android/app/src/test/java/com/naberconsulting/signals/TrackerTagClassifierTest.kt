package com.naberconsulting.signals

import com.naberconsulting.signals.capture.TrackerTagClassifier
import com.naberconsulting.signals.capture.TrackerTagClassifier.Advertisement
import com.naberconsulting.signals.capture.TrackerTagType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TrackerTagClassifierTest {

    private fun classify(
        manufacturerData: ByteArray? = null,
        serviceUuids: List<String> = emptyList(),
        serviceData: Map<String, ByteArray> = emptyMap(),
    ): TrackerTagType? =
        TrackerTagClassifier.classify(Advertisement(manufacturerData, serviceUuids, serviceData))

    @Test fun appleFindMyFrame() {
        assertEquals(
            TrackerTagType.APPLE_FIND_MY,
            classify(manufacturerData = byteArrayOf(0x4C, 0x00, 0x12, 0x19, 0x10)),
        )
    }

    @Test fun otherAppleAdvertisementIsNotATag() {
        assertNull(classify(manufacturerData = byteArrayOf(0x4C, 0x00, 0x07, 0x19)))
    }

    @Test fun nonAppleManufacturerIsNotATag() {
        assertNull(classify(manufacturerData = byteArrayOf(0x75, 0x00, 0x12, 0x19)))
    }

    @Test fun truncatedManufacturerDataIsNotATag() {
        assertNull(classify(manufacturerData = byteArrayOf(0x4C, 0x00)))
    }

    @Test fun serviceUuidTags() {
        assertEquals(TrackerTagType.TILE, classify(serviceUuids = listOf("FEED")))
        assertEquals(TrackerTagType.SAMSUNG_SMARTTAG, classify(serviceUuids = listOf("FD5A")))
        assertEquals(TrackerTagType.CHIPOLO, classify(serviceUuids = listOf("FE33")))
        assertEquals(TrackerTagType.SAMSUNG_SMARTTAG, classify(serviceUuids = listOf("fd5a")))
    }

    @Test fun unknownServiceUuidIsNotATag() {
        assertNull(classify(serviceUuids = listOf("180F", "180A")))
    }

    @Test fun googleFindMyDeviceFrame() {
        assertEquals(
            TrackerTagType.GOOGLE_FIND_MY_DEVICE,
            classify(serviceData = mapOf("FEAA" to byteArrayOf(0x40, 0xAB.toByte(), 0xCD.toByte()))),
        )
    }

    @Test fun classicEddystoneIsNotATag() {
        assertNull(classify(serviceData = mapOf("FEAA" to byteArrayOf(0x00, 0xAB.toByte()))))
    }

    @Test fun emptyAdvertisementIsNotATag() {
        assertNull(classify())
    }
}
