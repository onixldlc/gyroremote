package com.example.gyroremote

import android.annotation.SuppressLint
import android.app.Activity
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject

class MainActivity : Activity(), SensorEventListener {

    private lateinit var webView: WebView
    private lateinit var sensorManager: SensorManager
    private var rotationVector: Sensor? = null
    private var gyroscope: Sensor? = null
    @Volatile private var webReady = false

    private val rot = FloatArray(3)   // yaw, pitch, roll (deg)
    private val gyro = FloatArray(3)  // x, y, z (rad/s)

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.allowFileAccess = true
            webViewClient = WebViewClient()
            addJavascriptInterface(object {
                @JavascriptInterface fun ready() { webReady = true }
            }, "AndroidReady")
            loadUrl("file:///android_asset/index.html")
        }
        setContentView(webView)

        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        rotationVector = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    }

    override fun onResume() {
        super.onResume()
        rotationVector?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        gyroscope?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
    }

    override fun onPause() {
        super.onPause()
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                val R = FloatArray(9)
                val orientation = FloatArray(3)
                SensorManager.getRotationMatrixFromVector(R, event.values)
                SensorManager.getOrientation(R, orientation)
                rot[0] = Math.toDegrees(orientation[0].toDouble()).toFloat()
                rot[1] = Math.toDegrees(orientation[1].toDouble()).toFloat()
                rot[2] = Math.toDegrees(orientation[2].toDouble()).toFloat()
            }
            Sensor.TYPE_GYROSCOPE -> {
                gyro[0] = event.values[0]
                gyro[1] = event.values[1]
                gyro[2] = event.values[2]
            }
        }
        pushToJs()
    }

    private fun pushToJs() {
        if (!webReady) return
        val payload = JSONObject().apply {
            put("rot", JSONObject().apply {
                put("yaw", rot[0]); put("pitch", rot[1]); put("roll", rot[2])
            })
            put("gyro", JSONObject().apply {
                put("x", gyro[0]); put("y", gyro[1]); put("z", gyro[2])
            })
        }.toString()
        webView.post {
            webView.evaluateJavascript("window.onSensor && window.onSensor($payload);", null)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
