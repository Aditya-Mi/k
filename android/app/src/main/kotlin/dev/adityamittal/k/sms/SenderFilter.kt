package dev.adityamittal.k.sms

/**
 * Banks send from alphanumeric DLT headers ("AX-AXISBK-S", "JM-KOTAKB").
 * Plain phone numbers are people, so their messages are never queued or read
 * into Dart. Which header belongs to which bank is decided in Dart (txn_parser).
 */
object SenderFilter {
    fun isBusinessSender(address: String?): Boolean =
        !address.isNullOrBlank() && address.any { it.isLetter() }
}
