package com.directswitch.android

import com.directswitch.android.migrators.WhatsAppAttachmentKind
import com.directswitch.android.migrators.WhatsAppVaultReader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WhatsAppVaultReaderTest {

    @Test
    fun parsesIosWhatsAppTranscriptWithUnicodeLrmAndOpusVoiceNote() {
        val rawIos = """
            ‎[16/11/26, 15:30:12] Chat e chiamate sono crittografate end-to-end.
            [16/11/26, 15:31:05] Mario Rossi: Ciao Nicolas!
            Ti mando il vocale qui sotto
            ‎[16/11/26, 15:31:20] Mario Rossi: ‎<allegato: 00000005-AUDIO-2026-11-16-15-31-20.opus>
            [16/11/26, 15:32:00] Nicolas: Perfetto ricevuto!
        """.trimIndent()

        val parsed = WhatsAppVaultReader.parseTranscriptText(rawIos)
        assertEquals(4, parsed.size)
        assertTrue(parsed[0].isSystemNotice)

        assertEquals("Mario Rossi", parsed[1].sender)
        assertEquals("Ciao Nicolas!\nTi mando il vocale qui sotto", parsed[1].body)

        assertEquals("00000005-AUDIO-2026-11-16-15-31-20.opus", parsed[2].attachmentFileName)
        assertEquals(WhatsAppAttachmentKind.AUDIO_VOICE, parsed[2].attachmentKind)

        assertEquals("Nicolas", parsed[3].sender)
        assertEquals("Perfetto ricevuto!", parsed[3].body)
    }

    @Test
    fun parsesAndroidWhatsAppTranscriptAndCleansZipTitle() {
        val rawAndroid = """
            16/11/26, 15:40 - Giulia: Ecco la foto del documento
            16/11/26, 15:41 - Giulia: IMG-20261116-WA0004.jpg (file allegato)
        """.trimIndent()

        val parsed = WhatsAppVaultReader.parseTranscriptText(rawAndroid)
        assertEquals(2, parsed.size)
        assertEquals("Giulia", parsed[0].sender)
        assertEquals("IMG-20261116-WA0004.jpg", parsed[1].attachmentFileName)
        assertEquals(WhatsAppAttachmentKind.IMAGE, parsed[1].attachmentKind)

        assertEquals(
            "Mario Rossi",
            WhatsAppVaultReader.cleanChatTitleFromFileName("Chat WhatsApp con Mario Rossi.zip")
        )
    }
}
