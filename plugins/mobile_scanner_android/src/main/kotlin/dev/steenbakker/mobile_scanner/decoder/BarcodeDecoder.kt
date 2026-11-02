package dev.steenbakker.mobile_scanner.decoder

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Point
import android.graphics.Rect
import android.media.Image
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.Result
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.multi.qrcode.QRCodeMultiReader
import java.io.IOException
import java.util.concurrent.Callable
import java.util.concurrent.Executors

class InputImage private constructor(
    val width: Int,
    val height: Int,
    loadLuminance: () -> ByteArray,
    internal val rotation: Int,
) {
    internal constructor(width: Int, height: Int, bytes: ByteArray, rotation: Int) :
        this(width, height, { bytes }, rotation)

    internal val luminance: ByteArray by lazy(loadLuminance)
    companion object {
        fun fromMediaImage(image: Image, rotationDegrees: Int): InputImage {
            return InputImage(image.width, image.height, {
                val plane = image.planes[0]
                val buffer = plane.buffer.duplicate()
                val offset = buffer.position()
                val bytes = ByteArray(image.width * image.height)
                for (y in 0 until image.height) {
                    for (x in 0 until image.width) {
                        bytes[y * image.width + x] = buffer.get(offset + y * plane.rowStride + x * plane.pixelStride)
                    }
                }
                bytes
            }, rotationDegrees)
        }

        fun fromBitmap(bitmap: Bitmap?, rotationDegrees: Int): InputImage {
            val source = requireNotNull(bitmap)
            val pixels = IntArray(source.width * source.height)
            source.getPixels(pixels, 0, source.width, 0, 0, source.width, source.height)
            val bytes = ByteArray(pixels.size) { index ->
                val pixel = pixels[index]
                if (pixel ushr 24 == 0) 255.toByte() else {
                    val red = pixel shr 16 and 255
                    val green = pixel shr 8 and 255
                    val blue = pixel and 255
                    ((red + green * 2 + blue) / 4).toByte()
                }
            }
            return InputImage(source.width, source.height, bytes, rotationDegrees)
        }

        fun fromFilePath(context: Context, uri: Uri): InputImage {
            val bitmap = context.contentResolver.openInputStream(uri).use {
                BitmapFactory.decodeStream(it)
            } ?: throw IOException("Cannot decode image")
            try {
                val orientation = context.contentResolver.openInputStream(uri).use {
                    if (it == null) ExifInterface.ORIENTATION_NORMAL else ExifInterface(it)
                        .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                }
                val rotation = when (orientation) {
                    ExifInterface.ORIENTATION_ROTATE_180, ExifInterface.ORIENTATION_FLIP_VERTICAL -> 180
                    ExifInterface.ORIENTATION_ROTATE_90, ExifInterface.ORIENTATION_TRANSVERSE -> 90
                    ExifInterface.ORIENTATION_ROTATE_270, ExifInterface.ORIENTATION_TRANSPOSE -> 270
                    else -> 0
                }
                val frame = fromBitmap(bitmap, rotation)
                if (orientation in setOf(ExifInterface.ORIENTATION_FLIP_HORIZONTAL,
                        ExifInterface.ORIENTATION_FLIP_VERTICAL, ExifInterface.ORIENTATION_TRANSPOSE,
                        ExifInterface.ORIENTATION_TRANSVERSE)) {
                    for (y in 0 until frame.height) for (x in 0 until frame.width / 2) {
                        val left = y * frame.width + x
                        val right = y * frame.width + frame.width - 1 - x
                        val previous = frame.luminance[left]
                        frame.luminance[left] = frame.luminance[right]
                        frame.luminance[right] = previous
                    }
                }
                return frame
            } finally {
                bitmap.recycle()
            }
        }
    }
}

class Barcode(private val result: Result) {
    val rawValue: String? get() = result.text
    val rawBytes: ByteArray? get() = result.text?.toByteArray(Charsets.UTF_8)
    val format: Int get() = formats.entries.firstOrNull { it.value == result.barcodeFormat }?.key ?: -1
    val cornerPoints: Array<Point>? get() = result.resultPoints?.map { Point(it.x.toInt(), it.y.toInt()) }?.toTypedArray()
    val boundingBox: Rect? get() = cornerPoints?.takeIf { it.isNotEmpty() }?.let { points ->
        Rect(points.minOf { it.x }, points.minOf { it.y }, points.maxOf { it.x }, points.maxOf { it.y })
    }

    companion object {
        const val FORMAT_UNKNOWN = -1
        const val FORMAT_ALL_FORMATS = 0
        const val FORMAT_CODE_128 = 1
        const val FORMAT_CODE_39 = 2
        const val FORMAT_CODE_93 = 4
        const val FORMAT_CODABAR = 8
        const val FORMAT_DATA_MATRIX = 16
        const val FORMAT_EAN_13 = 32
        const val FORMAT_EAN_8 = 64
        const val FORMAT_ITF = 128
        const val FORMAT_QR_CODE = 256
        const val FORMAT_UPC_A = 512
        const val FORMAT_UPC_E = 1024
        const val FORMAT_PDF417 = 2048
        const val FORMAT_AZTEC = 4096
        internal val formats = mapOf(
            FORMAT_CODE_128 to com.google.zxing.BarcodeFormat.CODE_128,
            FORMAT_CODE_39 to com.google.zxing.BarcodeFormat.CODE_39,
            FORMAT_CODE_93 to com.google.zxing.BarcodeFormat.CODE_93,
            FORMAT_CODABAR to com.google.zxing.BarcodeFormat.CODABAR,
            FORMAT_DATA_MATRIX to com.google.zxing.BarcodeFormat.DATA_MATRIX,
            FORMAT_EAN_13 to com.google.zxing.BarcodeFormat.EAN_13,
            FORMAT_EAN_8 to com.google.zxing.BarcodeFormat.EAN_8,
            FORMAT_ITF to com.google.zxing.BarcodeFormat.ITF,
            FORMAT_QR_CODE to com.google.zxing.BarcodeFormat.QR_CODE,
            FORMAT_UPC_A to com.google.zxing.BarcodeFormat.UPC_A,
            FORMAT_UPC_E to com.google.zxing.BarcodeFormat.UPC_E,
            FORMAT_PDF417 to com.google.zxing.BarcodeFormat.PDF_417,
            FORMAT_AZTEC to com.google.zxing.BarcodeFormat.AZTEC,
        )
    }
}

class BarcodeScannerOptions private constructor(internal val formats: Set<Int>) {
    class Builder {
        private val formats = mutableSetOf<Int>()
        fun setBarcodeFormats(first: Int, vararg others: Int) = apply { formats.add(first); formats.addAll(others.toList()) }
        fun build() = BarcodeScannerOptions(formats.toSet())
    }
}

object BarcodeScanning {
    fun getClient(options: BarcodeScannerOptions? = null) = BarcodeScanner(options)
}

class BarcodeScanner(private val options: BarcodeScannerOptions?) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()

    fun process(image: InputImage): Task<List<Barcode>> = Tasks.call(executor, Callable { decode(image, options) })

    override fun close() { executor.shutdown() }

    companion object {
        internal fun decode(image: InputImage, options: BarcodeScannerOptions?): List<Barcode> {
            val quarterTurns = ((image.rotation % 360 + 360) % 360) / 90
            var width = image.width
            var height = image.height
            var bytes = image.luminance
            repeat(quarterTurns) {
                val rotated = ByteArray(bytes.size)
                for (y in 0 until height) for (x in 0 until width) {
                    rotated[x * height + height - 1 - y] = bytes[y * width + x]
                }
                bytes = rotated
                val previousWidth = width
                width = height
                height = previousWidth
            }
            val source = PlanarYUVLuminanceSource(bytes, width, height, 0, 0, width, height, false)
            val bitmap = BinaryBitmap(HybridBinarizer(source))
            val selected = options?.formats.orEmpty()
            val allowed = if (selected.isEmpty() || selected.contains(0)) Barcode.formats.values.toList()
                else selected.mapNotNull { Barcode.formats[it] }
            val hints = mapOf(DecodeHintType.POSSIBLE_FORMATS to allowed, DecodeHintType.TRY_HARDER to true)
            try {
                if (allowed.contains(com.google.zxing.BarcodeFormat.QR_CODE)) {
                    val results = try { QRCodeMultiReader().decodeMultiple(bitmap, hints).map(::Barcode) }
                        catch (_: NotFoundException) { emptyList() }
                    if (results.isNotEmpty()) return results
                }
                return listOf(Barcode(MultiFormatReader().decode(bitmap, hints)))
            } catch (_: NotFoundException) { return emptyList() }
        }
    }
}
