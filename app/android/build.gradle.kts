allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 일부 플러그인(receive_sharing_intent 등)은 Java 1.8/11 로 컴파일되는데, JBR 21 환경의
// Kotlin 타겟과 어긋나 AGP 8.10 의 JVM-target 검증에서 빌드가 실패한다.
// 모든 서브프로젝트(라이브러리 플러그인)의 Java·Kotlin JVM 타겟을 17 로 통일해 불일치를 없앤다.
// (:app 은 자체 build.gradle.kts 에서 17 로 설정한다.)
subprojects {
    plugins.withId("com.android.library") {
        extensions.getByType(com.android.build.gradle.LibraryExtension::class.java).compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions.jvmTarget = "17"
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
