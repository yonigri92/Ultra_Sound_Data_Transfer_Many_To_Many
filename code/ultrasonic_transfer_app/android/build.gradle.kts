import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.gradle.api.tasks.compile.JavaCompile
import com.android.build.gradle.BaseExtension
import org.gradle.api.JavaVersion

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// 1. מיישר את קוטלין וג'אווה ל-17
allprojects {
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
    
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
}

// 2. הפטיש האולטימטיבי: מדלג על האפליקציה כדי למנוע שגיאות, ומכריח את הספריות ל-SDK 34
subprojects {
    if (project.name != "app") {
        project.afterEvaluate {
            val androidExt = project.extensions.findByName("android") as? BaseExtension
            if (androidExt != null) {
                // דורס את הספרייה חזרה ל-34 אחרי שהיא סיימה להיטען
                androidExt.compileSdkVersion(34)
                androidExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                androidExt.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}