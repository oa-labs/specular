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

// AppFlowy Editor's mobile toolbar depends on keyboard_height_plugin 0.1.x,
// which still declares compileSdk 31. It uses an older Android Gradle Plugin,
// so register ahead of that subproject's evaluation and override its DSL before
// AGP locks the value.
gradle.beforeProject {
    if (path == ":keyboard_height_plugin") {
        afterEvaluate {
            extensions.findByName("android")?.let { androidExtension ->
                val method = androidExtension.javaClass.methods
                    .firstOrNull {
                        it.name == "setCompileSdkVersion" && it.parameterCount == 1
                    }
                if (method != null) {
                    val value = when (method.parameterTypes.single()) {
                        String::class.java -> "android-36"
                        else -> 36
                    }
                    method.invoke(androidExtension, value)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
