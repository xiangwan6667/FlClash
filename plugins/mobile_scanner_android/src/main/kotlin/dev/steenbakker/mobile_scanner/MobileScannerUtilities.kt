package dev.steenbakker.mobile_scanner

import android.graphics.ImageFormat
import android.graphics.Point
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import dev.steenbakker.mobile_scanner.decoder.Barcode
import java.io.ByteArrayOutputStream

fun Image.toByteArray(): ByteArray {
    val yBuffer = planes[0].buffer // Y
    val vuBuffer = planes[2].buffer // VU

    val ySize = yBuffer.remaining()
    val vuSize = vuBuffer.remaining()

    val nv21 = ByteArray(ySize + vuSize)

    yBuffer.get(nv21, 0, ySize)
    vuBuffer.get(nv21, ySize, vuSize)

    val yuvImage = YuvImage(nv21, ImageFormat.NV21, this.width, this.height, null)
    val out = ByteArrayOutputStream()
    yuvImage.compressToJpeg(Rect(0, 0, yuvImage.width, yuvImage.height), 50, out)
    return out.toByteArray()
}

val Barcode.data: Map<String, Any?>
    get() = mapOf(
        "corners" to cornerPoints?.map { mapOf("x" to it.x.toDouble(), "y" to it.y.toDouble()) },
        "displayValue" to rawValue,
        "format" to format,
        "rawBytes" to rawBytes,
        "rawValue" to rawValue,
        "type" to 7,
        "size" to boundingBox?.let { mapOf("width" to it.width().toDouble(), "height" to it.height().toDouble()) },
    )
