package dev.steenbakker.mobile_scanner.decoder

import android.graphics.Bitmap
import android.media.Image
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.RuntimeEnvironment
import org.mockito.Mockito
import java.nio.ByteBuffer
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BarcodeDecoderTest {
    private val payload = "https://example.com/subscription?token=public-test-value"
    private val options = BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()

    private fun image(rotation: Int = 0): InputImage {
        val matrix = QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, 240, 240)
        val data = ByteArray(matrix.width * matrix.height) { index ->
            if (matrix[index % matrix.width, index / matrix.width]) 0 else 255.toByte()
        }
        return InputImage(matrix.width, matrix.height, data, rotation)
    }

    @Test
    fun decodesLocalQrTextAtEveryCameraRotation() {
        for (rotation in listOf(0, 90, 180, 270)) {
            val result = BarcodeScanner.decode(image(rotation), options).single()
            assertEquals(payload, result.rawValue)
            assertEquals(Barcode.FORMAT_QR_CODE, result.format)
            assertArrayEquals(payload.toByteArray(), result.rawBytes)
            assertTrue(result.cornerPoints!!.isNotEmpty())
        }
    }

    @Test
    fun emptyFrameIsNotAnError() {
        val frame = InputImage(240, 240, ByteArray(240 * 240) { 255.toByte() }, 0)
        assertTrue(BarcodeScanner.decode(frame, options).isEmpty())
    }

    @Test
    fun galleryBitmapUsesTheSameOfflineDecoder() {
        val source = image()
        val bitmap = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(source.luminance.size) { if (source.luminance[it].toInt() == 0) -16777216 else -1 }
        bitmap.setPixels(pixels, 0, source.width, 0, 0, source.width, source.height)
        try {
            assertEquals(payload, BarcodeScanner.decode(InputImage.fromBitmap(bitmap, 0), options).single().rawValue)
        } finally {
            bitmap.recycle()
        }
    }

    @Test
    fun cameraLuminanceHonorsBufferPositionAndPaddedRows() {
        val source = image()
        val stride = source.width + 8
        val buffer = ByteBuffer.allocate(7 + stride * source.height)
        for (y in 0 until source.height) for (x in 0 until source.width) {
            buffer.put(7 + y * stride + x, source.luminance[y * source.width + x])
        }
        buffer.position(7)
        val plane = Mockito.mock(Image.Plane::class.java)
        Mockito.`when`(plane.buffer).thenReturn(buffer)
        Mockito.`when`(plane.rowStride).thenReturn(stride)
        Mockito.`when`(plane.pixelStride).thenReturn(1)
        val cameraImage = Mockito.mock(Image::class.java)
        Mockito.`when`(cameraImage.width).thenReturn(source.width)
        Mockito.`when`(cameraImage.height).thenReturn(source.height)
        Mockito.`when`(cameraImage.planes).thenReturn(arrayOf(plane))
        val frame = InputImage.fromMediaImage(cameraImage, 90)
        assertEquals(payload, BarcodeScanner.decode(frame, options).single().rawValue)
    }

    @Test
    fun galleryFileAppliesExifOrientationLocally() {
        val context = RuntimeEnvironment.getApplication()
        val file = File(context.cacheDir, "public-test-qr.jpg")
        val source = image()
        val bitmap = Bitmap.createBitmap(source.width, source.height + 20, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(-1)
        val pixels = IntArray(source.luminance.size) { if (source.luminance[it].toInt() == 0) -16777216 else -1 }
        bitmap.setPixels(pixels, 0, source.width, 0, 10, source.width, source.height)
        try {
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it) }
            ExifInterface(file).apply {
                setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_ROTATE_90.toString())
                saveAttributes()
            }
            val frame = InputImage.fromFilePath(context, Uri.fromFile(file))
            assertEquals(90, frame.rotation)
            assertEquals(source.width, frame.width)
            assertEquals(payload, BarcodeScanner.decode(frame, options).single().rawValue)
        } finally {
            bitmap.recycle()
            file.delete()
        }
    }
}
