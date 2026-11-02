package dev.steenbakker.mobile_scanner.objects

enum class BarcodeFormats(val intValue: Int) {
    UNKNOWN(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_UNKNOWN),
    ALL_FORMATS(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_ALL_FORMATS),
    CODE_128(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_CODE_128),
    CODE_39(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_CODE_39),
    CODE_93(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_CODE_93),
    CODABAR(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_CODABAR),
    DATA_MATRIX(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_DATA_MATRIX),
    EAN_13(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_EAN_13),
    EAN_8(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_EAN_8),
    ITF(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_ITF),
    QR_CODE(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_QR_CODE),
    UPC_A(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_UPC_A),
    UPC_E(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_UPC_E),
    PDF417(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_PDF417),
    AZTEC(dev.steenbakker.mobile_scanner.decoder.Barcode.FORMAT_AZTEC);

    companion object {
        fun fromRawValue(rawValue: Int): BarcodeFormats {
            return when(rawValue) {
                -1 -> UNKNOWN
                0 -> ALL_FORMATS
                1 -> CODE_128
                2 -> CODE_39
                4 -> CODE_93
                8 -> CODABAR
                16 -> DATA_MATRIX
                32 -> EAN_13
                64 -> EAN_8
                126, 127, 128 -> ITF
                256 -> QR_CODE
                512 -> UPC_A
                1024 -> UPC_E
                2048 -> PDF417
                4096 -> AZTEC
                else -> UNKNOWN
            }
        }
    }
}
