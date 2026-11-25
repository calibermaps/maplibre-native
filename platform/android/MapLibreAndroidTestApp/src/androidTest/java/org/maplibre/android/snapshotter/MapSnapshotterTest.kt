package org.maplibre.android.snapshotter

import android.graphics.PointF
import androidx.test.internal.runner.junit4.AndroidJUnit4ClassRunner
import androidx.test.rule.ActivityTestRule
import com.google.gson.JsonPrimitive
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.BackgroundLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.testapp.activity.FeatureOverviewActivity
import org.junit.Assert
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNotNull
import org.junit.Ignore
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.maplibre.android.testapp.styles.TestStyles
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Integration test that validates if a snapshotter creation
 */
@RunWith(AndroidJUnit4ClassRunner::class)
class MapSnapshotterTest {

    @Rule
    @JvmField
    var rule = ActivityTestRule(FeatureOverviewActivity::class.java)

    private val countDownLatch = CountDownLatch(1)

    @Test
    fun mapSnapshotter() {
        var mapSnapshotter: MapSnapshotter?
        rule.activity.runOnUiThread {
            val bg = BackgroundLayer("rand_tint")
            bg.setProperties(PropertyFactory.backgroundColor("rgba(255,128,0,0.7)"))
            val options = MapSnapshotter.Options(512, 512)
                .withPixelRatio(1.0f)
                .withStyleBuilder(
                    Style.Builder().fromUri(TestStyles.OPENFREEMAP_BRIGHT)
                        .withLayerAbove(bg, "country-label")
                )
                .withCameraPosition(
                    CameraPosition.Builder()
                        .zoom(12.0)
                        .target(LatLng(51.145495, 5.742234))
                        .build()
                )
            mapSnapshotter = MapSnapshotter(rule.activity, options)
            mapSnapshotter!!.start(
                {
                    assertNotNull(it)
                    assertNotNull(it.bitmap)
                    countDownLatch.countDown()
                },
                {
                    Assert.fail(it)
                }
            )
        }
        if (!countDownLatch.await(30, TimeUnit.SECONDS)) {
            throw TimeoutException()
        }
    }

    @Test
    fun mapSnapshotterStyleReloadResetsGlobalState() {
        var mapSnapshotter: MapSnapshotter?
        rule.activity.runOnUiThread {
            val styleJson = """
                {
                    "version": 8,
                    "state": {"showLabels": {"default": true}},
                    "sources": {},
                    "layers": []
                }
            """.trimIndent()
            val options = MapSnapshotter.Options(64, 64)
                .withPixelRatio(1.0f)
                .withStyleBuilder(Style.Builder().fromJson(styleJson))
            mapSnapshotter = MapSnapshotter(rule.activity, options)
            mapSnapshotter!!.start(
                {
                    Assert.assertEquals(
                        JsonPrimitive(true),
                        mapSnapshotter!!.getGlobalState().get("showLabels")
                    )

                    mapSnapshotter!!.setObserver(object : MapSnapshotter.Observer {
                        override fun onDidFinishLoadingStyle() {
                            Assert.assertEquals(
                                JsonPrimitive(true),
                                mapSnapshotter!!.getGlobalState().get("reloadState")
                            )
                            mapSnapshotter!!.setGlobalStateProperty("reloadState", JsonPrimitive(false))
                            Assert.assertEquals(
                                JsonPrimitive(false),
                                mapSnapshotter!!.getGlobalState().get("reloadState")
                            )
                            countDownLatch.countDown()
                        }

                        override fun onStyleImageMissing(imageName: String) {}
                    })
                    mapSnapshotter!!.setStyleUrl("asset://snapshotter_global_state_style.json")
                    // The previous style's state must not be visible, whether
                    // the asset finished loading synchronously or not.
                    Assert.assertNull(mapSnapshotter!!.getGlobalState().get("showLabels"))
                },
                {
                    Assert.fail(it)
                }
            )
        }
        if (!countDownLatch.await(30, TimeUnit.SECONDS)) {
            throw TimeoutException()
        }
    }

    @Test
    fun mapSnapshotterGlobalState() {
        var mapSnapshotter: MapSnapshotter?
        rule.activity.runOnUiThread {
            val styleJson = """
                {
                    "version": 8,
                    "state": {"showLabels": {"default": true}},
                    "sources": {},
                    "layers": []
                }
            """.trimIndent()
            val options = MapSnapshotter.Options(64, 64)
                .withPixelRatio(1.0f)
                .withStyleBuilder(Style.Builder().fromJson(styleJson))
            mapSnapshotter = MapSnapshotter(rule.activity, options)
            mapSnapshotter!!.start(
                {
                    // The style is fully loaded once the snapshot is ready;
                    // the default from the style's root "state" property applies.
                    Assert.assertEquals(
                        JsonPrimitive(true),
                        mapSnapshotter!!.getGlobalState().get("showLabels")
                    )

                    mapSnapshotter!!.setGlobalStateProperty("showLabels", JsonPrimitive(false))
                    Assert.assertEquals(
                        JsonPrimitive(false),
                        mapSnapshotter!!.getGlobalState().get("showLabels")
                    )
                    countDownLatch.countDown()
                },
                {
                    Assert.fail(it)
                }
            )
        }
        if (!countDownLatch.await(30, TimeUnit.SECONDS)) {
            throw TimeoutException()
        }
    }
    /**
     * Takes a snapshot of a pitched map over a 2000 m plateau, with or without 3D terrain, and
     * returns where the snapshot places [latLng] and the coordinate it gives back for that pixel.
     */
    private fun snapshotProjection(terrain: Boolean, latLng: LatLng): Pair<PointF, LatLng> {
        val done = CountDownLatch(1)
        var result: Pair<PointF, LatLng>? = null
        var failure: String? = null
        val terrainJson = if (terrain) """, "terrain": {"source": "dem", "exaggeration": 1.0}""" else ""
        val styleJson = """
            {
                "version": 8,
                "sources": {
                    "dem": {
                        "type": "raster-dem",
                        "tiles": ["asset://terrain_plateau_dem.png"],
                        "encoding": "mapbox",
                        "minzoom": 0,
                        "maxzoom": 0,
                        "tileSize": 256
                    }
                },
                "layers": [{"id": "background", "type": "background", "paint": {"background-color": "green"}}]
                $terrainJson
            }
        """.trimIndent()
        rule.activity.runOnUiThread {
            val options = MapSnapshotter.Options(256, 256)
                .withPixelRatio(1.0f)
                .withStyleBuilder(Style.Builder().fromJson(styleJson))
                .withCameraPosition(
                    CameraPosition.Builder()
                        .target(LatLng(46.0, 10.0))
                        .zoom(8.0)
                        .tilt(60.0)
                        .build()
                )
            val snapshotter = MapSnapshotter(rule.activity, options)
            snapshotter.start(
                {
                    val point = it.pixelForLatLng(latLng)
                    result = Pair(point, it.latLngForPixel(point))
                    done.countDown()
                },
                {
                    failure = it
                    done.countDown()
                }
            )
        }
        if (!done.await(30, TimeUnit.SECONDS)) {
            throw TimeoutException()
        }
        Assert.assertNull(failure, failure)
        return result!!
    }

    /**
     * With terrain a snapshot's point conversions answer on the draped surface, as the map's
     * Projection does: a point on a 2000 m plateau seen from a pitched camera sits higher on the
     * screen than the same point at sea level, and converting that pixel back gives the point.
     */
    @Test
    fun mapSnapshotConversionsAnswerOnTheTerrainSurface() {
        val ahead = LatLng(46.5, 10.0)
        val (flatPoint, flatBack) = snapshotProjection(false, ahead)
        val (terrainPoint, terrainBack) = snapshotProjection(true, ahead)

        assertTrue(
            "sea level y ${flatPoint.y}, terrain y ${terrainPoint.y}",
            terrainPoint.y < flatPoint.y - 3f
        )
        assertEquals(flatPoint.x, terrainPoint.x, 1f)
        assertEquals(ahead.latitude, terrainBack.latitude, 0.01)
        assertEquals(ahead.longitude, terrainBack.longitude, 0.01)
        // Without terrain nothing changes: the sea-level round trip.
        assertEquals(ahead.latitude, flatBack.latitude, 0.01)
    }
}
