allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// vosk_flutter_2 1.0.5's own android/build.gradle (in the pub cache, not
// something this app can edit directly) predates AGP's namespace
// requirement — it only declares `package="org.vosk.vosk_flutter"` in its
// AndroidManifest.xml, which this project's AGP version no longer accepts
// as a namespace source ("Namespace not specified" build failure). This is
// the standard workaround for that class of outdated plugin: inject the
// namespace from the root project instead of patching the pub cache.
subprojects {
    if (project.name == "vosk_flutter_2") {
        // Not afterEvaluate: this project.evaluationDependsOn(":app") setup
        // above evaluates vosk_flutter_2 (and its own internal AGP
        // afterEvaluate namespace check) before an afterEvaluate registered
        // here would ever fire. plugins.withId fires synchronously as soon
        // as vosk_flutter_2's own script applies com.android.library —
        // early enough to beat that check.
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                if (namespace == null) {
                    namespace = "org.vosk.vosk_flutter"
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
