import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release: la llave la custodia Luis y NUNCA se sube al repositorio (`key.properties` y `*.jks` están en el .gitignore).
// `android/key.properties` tiene storeFile, storePassword, keyAlias y keyPassword (ver docs/distribucion_apk.md).
val propiedadesDeFirma = Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) FileInputStream(archivo).use { load(it) }
}
val hayLlaveDeRelease = propiedadesDeFirma.getProperty("storeFile") != null

android {
    namespace = "com.lem.stockpilot"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lem.stockpilot"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayLlaveDeRelease) {
            create("release") {
                keyAlias = propiedadesDeFirma.getProperty("keyAlias")
                keyPassword = propiedadesDeFirma.getProperty("keyPassword")
                storeFile = rootProject.file(propiedadesDeFirma.getProperty("storeFile"))
                storePassword = propiedadesDeFirma.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Con la llave de Luis cuando existe `key.properties`; si no, la de depuración (solo para que `flutter run` en debug
            // y las pruebas sigan funcionando). Un release con la llave de depuración está BLOQUEADO más abajo, salvo que se pida
            // a propósito: ese APK no se puede repartir porque nunca podría actualizarse a uno firmado con la llave de Luis.
            signingConfig = if (hayLlaveDeRelease) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

// Impide fabricar por descuido un release firmado con la llave de depuración (la de cada computador): se podría repartir y luego no
// habría forma de actualizarlo sin desinstalar en cada celular. Para probar un release localmente, `STOCKPILOT_FIRMA_DEPURACION=1`.
gradle.taskGraph.whenReady {
    val esRelease = allTasks.any { t ->
        t.name.contains("Release", ignoreCase = true) &&
            (t.name.startsWith("assemble") || t.name.startsWith("package") || t.name.startsWith("bundle"))
    }
    if (esRelease && !hayLlaveDeRelease && System.getenv("STOCKPILOT_FIRMA_DEPURACION") != "1") {
        throw GradleException(
            "Falta android/key.properties: un release se firma con la llave de Luis y no se reparte firmado con la de depuración. " +
                "Para probar un release solo en tu equipo: STOCKPILOT_FIRMA_DEPURACION=1 (ese APK no es repartible)."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
