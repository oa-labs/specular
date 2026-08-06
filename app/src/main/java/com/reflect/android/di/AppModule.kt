package com.reflect.android.di

import android.content.Context
import androidx.room.Room
import androidx.work.WorkManager
import com.reflect.android.data.local.FileStore
import com.reflect.android.data.local.SpecularDatabase
import com.reflect.android.data.remote.GitHubApi
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides @Singleton
    fun provideMoshi(): Moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()

    @Provides @Singleton
    fun provideOkHttp(): OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(HttpLoggingInterceptor().apply { level = HttpLoggingInterceptor.Level.BASIC })
        .build()

    @Provides @Singleton
    fun provideGitHubApi(moshi: Moshi, okHttp: OkHttpClient): GitHubApi =
        Retrofit.Builder()
            .baseUrl("https://api.github.com/")
            .client(okHttp)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(GitHubApi::class.java)

    @Provides @Singleton
    fun provideDatabase(@ApplicationContext context: Context): SpecularDatabase =
        Room.databaseBuilder(context, SpecularDatabase::class.java, "reflect.db")
            .fallbackToDestructiveMigration()
            .build()

    @Provides fun provideNoteDao(db: SpecularDatabase) = db.noteDao()

    @Provides @Singleton
    fun provideFileStore(@ApplicationContext context: Context) = FileStore(context)

    @Provides @Singleton
    fun provideWorkManager(@ApplicationContext context: Context): WorkManager =
        WorkManager.getInstance(context)
}
