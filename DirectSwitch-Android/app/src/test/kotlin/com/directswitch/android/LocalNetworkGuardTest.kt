package com.directswitch.android

import com.directswitch.android.transport.LocalNetworkAddresses
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalNetworkGuardTest {

    @Test
    fun acceptsPrivateAndHotspotRanges() {
        listOf("10.0.0.5", "172.16.0.1", "172.31.255.254", "192.168.43.1", "192.168.1.20", "169.254.10.2")
            .forEach { assertTrue("$it deve essere locale", LocalNetworkAddresses.isLocalNetworkIpv4(it)) }
    }

    @Test
    fun rejectsPublicAndMalformedAddresses() {
        listOf("8.8.8.8", "172.15.0.1", "172.32.0.1", "192.169.1.1", "1.2.3", "192.168.1.256", "abc", "", "192.168.1.1.5", "evil.example.com")
            .forEach { assertFalse("$it NON deve essere locale", LocalNetworkAddresses.isLocalNetworkIpv4(it)) }
    }
}
